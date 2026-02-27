import '../../models/conversation.dart';

class MessageSlice {
  const MessageSlice({required this.messages, required this.includeSummary});

  final List<ConversationMessage> messages;
  final bool includeSummary;
}

class PendingSummary {
  const PendingSummary({
    required this.taskId,
    required this.anchorMessageId,
    required this.sourceText,
    required this.promptMessageId,
  });

  final int taskId;
  final String anchorMessageId;
  final String sourceText;
  final String promptMessageId;
}

class TokenCacheEntry {
  const TokenCacheEntry({required this.text, required this.count});

  final String text;
  final int count;
}

class ThoughtEntry {
  const ThoughtEntry({required this.text});

  final String text;
}

class StreamParseState {
  String buffer = '';
  String visible = '';
  String thought = '';
  bool inThought = false;
}

class TagMatch {
  const TagMatch({required this.index, required this.tag});

  final int index;
  final String tag;
}

class ChatSnapshot {
  const ChatSnapshot({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.data,
  });

  final String id;
  final String name;
  final int timestamp;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'timestamp': timestamp,
      'data': data,
    };
  }

  static ChatSnapshot fromJson(Map<String, dynamic> json) {
    return ChatSnapshot(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      timestamp: (json['timestamp'] as int?) ?? 0,
      data: (json['data'] as Map?)?.map((Object? k, Object? v) => MapEntry('$k', v)) ??
          <String, dynamic>{},
    );
  }
}
