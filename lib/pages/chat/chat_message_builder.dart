import '../../models/conversation.dart';
import 'chat_stream_parser.dart';

class ChatMessageBuilder {
  static List<Map<String, String>> buildMessagesFrom({
    required String systemPrompt,
    required List<ConversationMessage> messages,
    String? summaryText,
    String? summaryPrefix,
    String? extraUserText,
  }) {
    final List<Map<String, String>> payload = <Map<String, String>>[];
    if (systemPrompt.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': systemPrompt.trim()});
    }
    if (summaryText != null &&
        summaryText.trim().isNotEmpty &&
        summaryPrefix != null &&
        summaryPrefix.isNotEmpty) {
      payload.add(<String, String>{
        'role': 'system',
        'content': '${summaryPrefix}${summaryText.trim()}',
      });
    }
    for (final ConversationMessage message in messages) {
      if (message.kind != 'message') {
        continue;
      }
      final String content = stripThoughtTags(message.text);
      payload.add(<String, String>{
        'role': message.role,
        'content': content,
      });
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }
}
