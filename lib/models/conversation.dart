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
    this.speakerTaId,
  });

  final String id;
  final String role;
  final String text;
  final int timestamp;
  final String kind;
  final String? summaryId;
  final String? anchorMessageId;
  final String? speakerTaId;

  ConversationMessage copyWith({String? text, String? speakerTaId}) {
    return ConversationMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      kind: kind,
      summaryId: summaryId,
      anchorMessageId: anchorMessageId,
      speakerTaId: speakerTaId ?? this.speakerTaId,
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
