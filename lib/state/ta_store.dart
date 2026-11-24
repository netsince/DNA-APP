import 'package:dna/models/ta.dart';
import 'package:dna/services/hive_service.dart';

/// 角色卡这一域的**状态与写操作**（拆出 `AppController` 的第二块）。
///
/// 只有「列表 / 查 by id / 增删改 / 归档 / 排序 / 落盘」。**群聊成员的摘除不在
/// 这里**：那要改会话数据，属于会话域，由 `AppController.deleteTa` 收尾
/// （见 `_pruneTaFromGroups`）。
///
/// 通知不在这里发：构造时传 `onChanged`，由 `AppController` 接到
/// `AppChange.data` 分组。
class TaStore {
  TaStore({required HiveService hive, required void Function() onChanged})
    : _hive = hive,
      _onChanged = onChanged;

  final HiveService _hive;
  final void Function() _onChanged;

  List<TA> _items = <TA>[];

  /// 只读视图（外部拿到的列表不可改）。
  List<TA> get items => List<TA>.unmodifiable(_items);

  List<TA> get activeItems =>
      _items.where((TA t) => !t.archived).toList(growable: false);

  TA? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final TA ta in _items) {
      if (ta.id == id) return ta;
    }
    return null;
  }

  /// id → 角色（导出时解析说话人 / 内嵌角色卡用）。
  Map<String, TA> get byIdMap {
    final Map<String, TA> map = <String, TA>{};
    for (final TA ta in _items) {
      map[ta.id] = ta;
    }
    return map;
  }

  /// 整体替换（启动加载 / 导入 / 清空数据）。不落盘、不通知。
  void replaceAll(Iterable<TA> tas) {
    _items = List<TA>.from(tas);
  }

  Future<void> upsert(TA ta) async {
    final int index = _items.indexWhere((TA item) => item.id == ta.id);
    if (index == -1) {
      _items = <TA>[..._items, ta];
    } else {
      final List<TA> updated = <TA>[..._items];
      updated[index] = ta;
      _items = updated;
    }
    await _hive.upsertTa(ta);
    _onChanged();
  }

  Future<void> delete(String id) async {
    _items = _items.where((TA ta) => ta.id != id).toList();
    await _hive.deleteTa(id);
    _onChanged();
  }

  Future<void> setArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _items.indexWhere((TA item) => item.id == id);
    if (index == -1) return;
    final TA current = _items[index];
    if (current.archived == archived) return;
    final List<TA> updated = <TA>[..._items];
    updated[index] = current.copyWith(archived: archived);
    _items = updated;
    await _hive.upsertTa(updated[index]);
    _onChanged();
  }

  /// 排序：下标口径是「移除之后」。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    final List<TA> updated = List<TA>.from(_items);
    final TA moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _items = updated;
    await _hive.saveTas(_items);
    _onChanged();
  }

  /// 把当前列表整体落盘（导入流程改完列表后调用）。
  Future<void> persist() => _hive.saveTas(_items);
}
