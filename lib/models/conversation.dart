import 'message_attachment.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.taId,
    required this.worldId,
    required this.note,
    required this.messages,
    required this.backgroundMode,
    required this.summaries,
    required this.archived,
    required this.isGroup,
    required this.groupName,
    required this.groupPrompt,
    required this.memberTaIds,
    required this.activeTaId,
    this.identityId,
    this.pinned = false,
    this.bgmAnimated = false,
  });

  final String id;
  final String taId;
  final String? worldId;
  final String note;
  final List<ConversationMessage> messages;
  final String backgroundMode;
  final List<ConversationSummary> summaries;
  final bool archived;
  final bool isGroup;
  final String groupName;
  final String groupPrompt;
  final List<String> memberTaIds;
  final String? activeTaId;

  /// 用户选择的本聊天中使用的身份 ID（可选）。
  final String? identityId;

  /// 是否置顶：置顶的会话在列表中排在前面。
  final bool pinned;

  /// 动态背景（GIF 立绘）是否播放动画。跟随当前会话持久化。
  /// false = 暂停，仅显示第一帧（默认）；true = 继续播放动画。
  final bool bgmAnimated;

  Conversation copyWith({
    String? taId,
    String? worldId,
    String? note,
    List<ConversationMessage>? messages,
    String? backgroundMode,
    List<ConversationSummary>? summaries,
    bool? archived,
    bool? isGroup,
    String? groupName,
    String? groupPrompt,
    List<String>? memberTaIds,
    String? activeTaId,
    String? identityId,
    bool? pinned,
    bool? bgmAnimated,
  }) {
    return Conversation(
      id: id,
      taId: taId ?? this.taId,
      worldId: worldId ?? this.worldId,
      note: note ?? this.note,
      messages: messages ?? this.messages,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      summaries: summaries ?? this.summaries,
      archived: archived ?? this.archived,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      groupPrompt: groupPrompt ?? this.groupPrompt,
      memberTaIds: memberTaIds ?? this.memberTaIds,
      activeTaId: activeTaId ?? this.activeTaId,
      identityId: identityId ?? this.identityId,
      pinned: pinned ?? this.pinned,
      bgmAnimated: bgmAnimated ?? this.bgmAnimated,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'taId': taId,
      'worldId': worldId,
      'note': note,
      'backgroundMode': backgroundMode,
      'messages': messages.map((ConversationMessage m) => m.toJson()).toList(),
      'summaries': summaries.map((ConversationSummary s) => s.toJson()).toList(),
      'archived': archived,
      'isGroup': isGroup,
      'groupName': groupName,
      'groupPrompt': groupPrompt,
      'memberTaIds': memberTaIds,
      'activeTaId': activeTaId,
      'identityId': identityId,
      'pinned': pinned,
      'bgmAnimated': bgmAnimated,
    };
  }

  static Conversation fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['messages'] as List<dynamic>?;
    final List<dynamic>? rawSummaries = json['summaries'] as List<dynamic>?;
    final String taId = (json['taId'] as String?) ?? '';
    final bool isGroup = (json['isGroup'] as bool?) ?? false;
    final List<String> rawMembers =
        (json['memberTaIds'] as List?)?.whereType<String>().toList() ?? <String>[];
    final List<String> memberTaIds = isGroup
        ? <String>[
            if (taId.isNotEmpty) taId,
            ...rawMembers.where((String id) => id != taId),
          ]
        : <String>[taId];
    final String? rawActive = json['activeTaId'] as String?;
    final String activeTaId = (rawActive != null && rawActive.isNotEmpty)
        ? rawActive
        : (memberTaIds.isNotEmpty ? memberTaIds.first : taId);
    return Conversation(
      id: json['id'] as String,
      taId: taId,
      worldId: json['worldId'] as String?,
      note: (json['note'] as String?) ?? '',
      backgroundMode: (json['backgroundMode'] as String?) ?? 'none',
      messages: raw == null
          ? <ConversationMessage>[]
          : raw
              .whereType<Map<String, dynamic>>()
              .map(ConversationMessage.fromJson)
              .toList(),
      summaries: rawSummaries == null
          ? <ConversationSummary>[]
          : rawSummaries
              .whereType<Map<String, dynamic>>()
              .map(ConversationSummary.fromJson)
              .toList(),
      archived: (json['archived'] as bool?) ?? false,
      isGroup: isGroup,
      groupName: (json['groupName'] as String?) ?? '',
      groupPrompt: (json['groupPrompt'] as String?) ?? '',
      memberTaIds: memberTaIds,
      activeTaId: activeTaId,
      identityId: json['identityId'] as String?,
      pinned: (json['pinned'] as bool?) ?? false,
      bgmAnimated: (json['bgmAnimated'] as bool?) ?? false,
    );
  }
}

/// 消息类型。存的是字符串（历史数据 + 序列化稳定），比较时用类型。
///
/// 为什么要有它：`kind` 是裸字符串，全项目 28 处字面量比较（`== 'message'`、
/// `!= 'summary'`…），拼错一个字母编译器不管，只会在运行时表现为「这条消息不
/// 该出现却出现了」或「该进请求却没进」。有了枚举 + [tryOf]，比较点改成
/// `kindEnum == MessageKind.summary`，拼错直接编译失败。
///
/// 为什么用 `tryOf` 而不是 `of`：未知的 kind（老数据/未来新增）必须**保持原有语义**
/// —— 现在所有比较都是「等于某个已知值才处理」，未知值一律不匹配。返回 null 正好等价；
/// 如果默认成 `message`，未知类型会被当成普通消息塞进请求，那是行为改变。
enum MessageKind {
  message('message'),
  summary('summary'),
  summaryPrompt('summary_prompt');

  const MessageKind(this.value);

  /// 序列化进 JSON / Hive 的原始字符串。
  final String value;

  /// 原始字符串 → 类型；未知值返回 null（调用方按「不是已知类型」处理，与以前一致）。
  static MessageKind? tryOf(String raw) => switch (raw) {
    'message' => message,
    'summary' => summary,
    'summary_prompt' => summaryPrompt,
    _ => null,
  };
}
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.kind = 'message',
    this.summaryId,
    this.anchorMessageId,
    this.speakerTaId,
    this.attachments = const <MessageAttachment>[],
  });

  final String id;
  final String role;
  final String text;
  final int timestamp;
  final String kind;

  /// [kind] 的类型化视图；未知值返回 null（见 [MessageKind.tryOf]）。
  MessageKind? get kindEnum => MessageKind.tryOf(kind);
  final String? summaryId;
  final String? anchorMessageId;
  final String? speakerTaId;

  /// 本条消息携带的附件（旧数据为空列表）。
  final List<MessageAttachment> attachments;

  ConversationMessage copyWith({
    String? text,
    String? speakerTaId,
    List<MessageAttachment>? attachments,
  }) {
    return ConversationMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      kind: kind,
      summaryId: summaryId,
      anchorMessageId: anchorMessageId,
      speakerTaId: speakerTaId ?? this.speakerTaId,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role,
      'text': text,
      'timestamp': timestamp,
      'kind': kind,
      'summaryId': summaryId,
      'anchorMessageId': anchorMessageId,
      'speakerTaId': speakerTaId,
      if (attachments.isNotEmpty)
        'attachments': <Map<String, dynamic>>[
          for (final MessageAttachment a in attachments) a.toJson(),
        ],
    };
  }

  static ConversationMessage fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] as String,
      role: (json['role'] as String?) ?? 'user',
      text: (json['text'] as String?) ?? '',
      timestamp: (json['timestamp'] as int?) ?? 0,
      kind: (json['kind'] as String?) ?? 'message',
      summaryId: json['summaryId'] as String?,
      anchorMessageId: json['anchorMessageId'] as String?,
      speakerTaId: json['speakerTaId'] as String?,
      attachments: parseAttachments(json['attachments']),
    );
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.endMessageId,
  });

  final String id;
  final String text;
  final int createdAt;
  final String endMessageId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'createdAt': createdAt,
      'endMessageId': endMessageId,
    };
  }

  static ConversationSummary fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      text: (json['text'] as String?) ?? '',
      createdAt: (json['createdAt'] as int?) ?? 0,
      endMessageId: (json['endMessageId'] as String?) ?? '',
    );
  }
}
