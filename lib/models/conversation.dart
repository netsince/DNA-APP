class Conversation {
  const Conversation({
    required this.id,
    required this.roleId,
    required this.worldId,
    required this.note,
    required this.messages,
    required this.backgroundMode,
    required this.summaries,
    required this.archived,
  });

  final String id;
  final String roleId;
  final String? worldId;
  final String note;
  final List<ConversationMessage> messages;
  final String backgroundMode;
  final List<ConversationSummary> summaries;
  final bool archived;

  Conversation copyWith({
    String? roleId,
    String? worldId,
    String? note,
    List<ConversationMessage>? messages,
    String? backgroundMode,
    List<ConversationSummary>? summaries,
    bool? archived,
  }) {
    return Conversation(
      id: id,
      roleId: roleId ?? this.roleId,
      worldId: worldId ?? this.worldId,
      note: note ?? this.note,
      messages: messages ?? this.messages,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      summaries: summaries ?? this.summaries,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'roleId': roleId,
      'worldId': worldId,
      'note': note,
      'backgroundMode': backgroundMode,
      'messages': messages.map((ConversationMessage m) => m.toJson()).toList(),
      'summaries': summaries.map((ConversationSummary s) => s.toJson()).toList(),
      'archived': archived,
    };
  }

  static Conversation fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['messages'] as List<dynamic>?;
    final List<dynamic>? rawSummaries = json['summaries'] as List<dynamic>?;
    return Conversation(
      id: json['id'] as String,
      roleId: json['roleId'] as String,
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
    );
  }
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
  });

  final String id;
  final String role;
  final String text;
  final int timestamp;
  final String kind;
  final String? summaryId;
  final String? anchorMessageId;

  ConversationMessage copyWith({String? text}) {
    return ConversationMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      kind: kind,
      summaryId: summaryId,
      anchorMessageId: anchorMessageId,
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
