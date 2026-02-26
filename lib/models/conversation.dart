class Conversation {
  const Conversation({
    required this.id,
    required this.roleId,
    required this.worldId,
    required this.note,
    required this.messages,
    required this.backgroundMode,
  });

  final String id;
  final String roleId;
  final String? worldId;
  final String note;
  final List<ConversationMessage> messages;
  final String backgroundMode;

  Conversation copyWith({
    String? roleId,
    String? worldId,
    String? note,
    List<ConversationMessage>? messages,
    String? backgroundMode,
  }) {
    return Conversation(
      id: id,
      roleId: roleId ?? this.roleId,
      worldId: worldId ?? this.worldId,
      note: note ?? this.note,
      messages: messages ?? this.messages,
      backgroundMode: backgroundMode ?? this.backgroundMode,
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
    };
  }

  static Conversation fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['messages'] as List<dynamic>?;
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
    );
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String role;
  final String text;
  final int timestamp;

  ConversationMessage copyWith({String? text}) {
    return ConversationMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role,
      'text': text,
      'timestamp': timestamp,
    };
  }

  static ConversationMessage fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] as String,
      role: (json['role'] as String?) ?? 'user',
      text: (json['text'] as String?) ?? '',
      timestamp: (json['timestamp'] as int?) ?? 0,
    );
  }
}
