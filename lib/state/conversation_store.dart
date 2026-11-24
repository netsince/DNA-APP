import 'package:dna/models/conversation.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/utils/id_utils.dart';

/// 会话这一域的**状态与写操作**（拆出 `AppController` 的第四块）。
///
/// 单聊与群聊是两个列表（历史上分开存，排序/置顶/归档各管各的），但对调用方
/// 表现为「按 id 查得到、按 id 写回不串味」。这里把两个列表连同它们之间的
/// **保护规则**一起收进来：
///
/// * 群聊身份由创建时决定。单聊形态的 payload 写到已有群聊 id 上时，必须把
///   群聊专属字段（成员、群名、群设定、当前发言人）从**库里的旧值**还原 ——
///   单聊 payload 对它们「没有主张」，直接落库等于拿「没有意见」覆盖真实数据
///   （Hive 按 id 覆盖，成员/群设定/说话人标注会一起消失，且不报错）。
///
/// 通知不在这里发：构造时传 `onChanged`，由 `AppController` 接到
/// `AppChange.data`。
class ConversationStore {
  ConversationStore({
    required HiveService hive,
    required void Function() onChanged,
  }) : _hive = hive,
       _onChanged = onChanged;

  final HiveService _hive;
  final void Function() _onChanged;

  List<Conversation> _singles = <Conversation>[];
  List<Conversation> _groups = <Conversation>[];

  List<Conversation> get items => List<Conversation>.unmodifiable(_singles);
  List<Conversation> get groups => List<Conversation>.unmodifiable(_groups);
  List<Conversation> get all => <Conversation>[..._singles, ..._groups];

  Conversation? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final Conversation c in _singles) {
      if (c.id == id) return c;
    }
    for (final Conversation c in _groups) {
      if (c.id == id) return c;
    }
    return null;
  }

  Conversation? groupById(String id) {
    for (final Conversation c in _groups) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool isKnownGroupId(String id) =>
      _groups.any((Conversation item) => item.id == id);

  /// 整体替换（启动加载 / 导入 / 清空数据）。不落盘、不通知。
  void replaceAll({
    required Iterable<Conversation> singles,
    required Iterable<Conversation> groups,
  }) {
    _singles = List<Conversation>.from(singles);
    _groups = List<Conversation>.from(groups);
  }

  /// 整体替换群聊列表（跨域收尾用：删角色后把成员摘干净）。不落盘、不通知。
  void replaceGroups(Iterable<Conversation> groups) {
    _groups = List<Conversation>.from(groups);
  }

  /// 写回会话。群聊 id 上的单聊 payload 会被还原成群聊（见类注释）。
  Future<void> upsert(Conversation conversation) async {
    if (conversation.isGroup) {
      await upsertGroup(conversation);
      return;
    }
    if (isKnownGroupId(conversation.id)) {
      await upsertGroup(_restoreGroupFields(conversation));
      return;
    }
    final int index = _singles.indexWhere((Conversation item) => item.id == conversation.id);
    if (index == -1) {
      _singles = <Conversation>[..._singles, conversation];
    } else {
      final List<Conversation> updated = <Conversation>[..._singles];
      updated[index] = conversation;
      _singles = updated;
    }
    await _hive.upsertConversation(conversation);
    _onChanged();
  }

  Future<void> upsertGroup(Conversation conversation) async {
    if (!conversation.isGroup) {
      conversation = conversation.copyWith(isGroup: true);
    }
    final int index =
        _groups.indexWhere((Conversation item) => item.id == conversation.id);
    if (index == -1) {
      _groups = <Conversation>[..._groups, conversation];
    } else {
      final List<Conversation> updated = <Conversation>[..._groups];
      updated[index] = conversation;
      _groups = updated;
    }
    await _hive.upsertConversation(conversation);
    _onChanged();
  }

  Conversation _restoreGroupFields(Conversation incoming) {
    final Conversation? stored = groupById(incoming.id);
    if (stored == null) {
      return incoming.copyWith(isGroup: true);
    }
    return incoming.copyWith(
      isGroup: true,
      memberTaIds: stored.memberTaIds,
      activeTaId: stored.activeTaId,
      groupName: stored.groupName,
      groupPrompt: stored.groupPrompt,
    );
  }

  Future<void> delete(String id) async {
    _singles = _singles.where((Conversation item) => item.id != id).toList();
    await _hive.deleteConversation(id);
    _onChanged();
  }

  Future<void> deleteGroup(String id) async {
    _groups = _groups.where((Conversation item) => item.id != id).toList();
    await _hive.deleteConversation(id);
    _onChanged();
  }

  Future<void> setArchived({required String id, required bool archived}) =>
      _updateSingle(id, (Conversation c) => c.copyWith(archived: archived),
          (Conversation c) => c.archived == archived);

  Future<void> setPinned({required String id, required bool pinned}) =>
      _updateSingle(id, (Conversation c) => c.copyWith(pinned: pinned),
          (Conversation c) => c.pinned == pinned);

  Future<void> setGroupPinned({required String id, required bool pinned}) =>
      _updateGroup(id, (Conversation c) => c.copyWith(pinned: pinned),
          (Conversation c) => c.pinned == pinned);

  Future<void> setGroupArchived({
    required String id,
    required bool archived,
  }) =>
      _updateGroup(id, (Conversation c) => c.copyWith(archived: archived),
          (Conversation c) => c.archived == archived);

  Future<void> _updateSingle(
    String id,
    Conversation Function(Conversation) change,
    bool Function(Conversation) isNoop,
  ) async {
    final int index = _singles.indexWhere((Conversation item) => item.id == id);
    if (index == -1) return;
    final Conversation current = _singles[index];
    if (isNoop(current)) return;
    final List<Conversation> updated = <Conversation>[..._singles];
    updated[index] = change(current);
    _singles = updated;
    await _hive.upsertConversation(updated[index]);
    _onChanged();
  }

  Future<void> _updateGroup(
    String id,
    Conversation Function(Conversation) change,
    bool Function(Conversation) isNoop,
  ) async {
    final int index = _groups.indexWhere((Conversation item) => item.id == id);
    if (index == -1) return;
    final Conversation current = _groups[index];
    if (isNoop(current)) return;
    final List<Conversation> updated = <Conversation>[..._groups];
    updated[index] = change(current);
    _groups = updated;
    await _hive.upsertConversation(updated[index]);
    _onChanged();
  }

  /// 复制一个会话：全新会话 id 与消息 id，其余（角色、世界、身份、群成员、
  /// 消息、摘要）与源一致。副本不置顶、不归档，插在源之后。返回副本 id。
  Future<String> duplicate(String id) async {
    final Conversation? source = byId(id);
    if (source == null) {
      throw StateError('会话不存在：$id');
    }
    final String newConvId = _uniqueId();
    final Conversation copy = Conversation(
      id: newConvId,
      taId: source.taId,
      worldId: source.worldId,
      note: source.note.trim().isEmpty ? '副本' : '${source.note}（副本）',
      messages: source.messages
          .map(
            (ConversationMessage m) => ConversationMessage(
              id: newId(),
              role: m.role,
              text: m.text,
              timestamp: m.timestamp,
              kind: m.kind,
              summaryId: m.summaryId,
              anchorMessageId: m.anchorMessageId,
              speakerTaId: m.speakerTaId,
            ),
          )
          .toList(),
      backgroundMode: source.backgroundMode,
      summaries: source.summaries
          .map(
            (ConversationSummary s) => ConversationSummary(
              id: newId(),
              text: s.text,
              createdAt: s.createdAt,
              endMessageId: s.endMessageId,
            ),
          )
          .toList(),
      archived: false,
      isGroup: source.isGroup,
      groupName: source.groupName,
      groupPrompt: source.groupPrompt,
      memberTaIds: source.memberTaIds,
      activeTaId: source.activeTaId,
      identityId: source.identityId,
      pinned: false,
    );

    if (copy.isGroup) {
      final int at = _groups.indexWhere((Conversation c) => c.id == id);
      final List<Conversation> updated = <Conversation>[..._groups];
      updated.insert(at == -1 ? updated.length : at + 1, copy);
      _groups = updated;
    } else {
      final int at = _singles.indexWhere((Conversation c) => c.id == id);
      final List<Conversation> updated = <Conversation>[..._singles];
      updated.insert(at == -1 ? updated.length : at + 1, copy);
      _singles = updated;
    }
    await _hive.upsertConversation(copy);
    _onChanged();
    return newConvId;
  }

  String _uniqueId() {
    final Set<String> existing = <String>{
      for (final Conversation c in _singles) c.id,
      for (final Conversation c in _groups) c.id,
    };
    String id = newId();
    while (existing.contains(id)) {
      id = newId();
    }
    return id;
  }

  /// 按 [orderedIds] 重排单聊列表里属于这些 id 的那一段，其余保持原位。
  Future<void> reorderSubset(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final Set<String> subset = orderedIds.toSet();
    if (subset.length != orderedIds.length) return;
    final Map<String, Conversation> byIdMap = <String, Conversation>{
      for (final Conversation c in _singles) c.id: c,
    };
    for (final String id in orderedIds) {
      if (!byIdMap.containsKey(id)) return;
    }
    int cursor = 0;
    final List<Conversation> updated = <Conversation>[];
    for (final Conversation c in _singles) {
      if (!subset.contains(c.id)) {
        updated.add(c);
        continue;
      }
      updated.add(byIdMap[orderedIds[cursor]]!);
      cursor += 1;
    }
    _singles = updated;
    await _hive.saveConversations(_singles);
    _onChanged();
  }

  /// 把两个列表整体落盘（导入流程改完列表后调用）。
  Future<void> persist() => _hive.saveConversations(<Conversation>[..._singles, ..._groups]);
}
