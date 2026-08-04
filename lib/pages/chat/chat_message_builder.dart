import '../../models/conversation.dart';
import 'chat_stream_parser.dart';

class ChatMessageBuilder {
  /// 把一条历史消息转成发给模型的 content。群聊时（prefixSpeaker 开启）给
  /// AI 角色的发言加"角色名："前缀，让模型从历史中分清每句话是谁说的。
  static String resolveContentWithSpeaker({
    required ConversationMessage message,
    required bool prefixSpeaker,
    String? Function(String? speakerTaId)? speakerNameResolver,
  }) {
    String content = stripThoughtTags(message.text);
    if (prefixSpeaker &&
        message.role == 'assistant' &&
        speakerNameResolver != null) {
      final String? name = speakerNameResolver(message.speakerTaId);
      if (name != null && name.isNotEmpty) {
        content = '$name：$content';
      }
    }
    return content;
  }

  static List<Map<String, String>> buildMessagesFrom({
    required String systemPrompt,
    required List<ConversationMessage> messages,
    String? summaryText,
    String? summaryPrefix,
    String? extraUserText,
    bool prefixSpeaker = false,
    String? Function(String? speakerTaId)? speakerNameResolver,
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
        'content': '$summaryPrefix${summaryText.trim()}',
      });
    }
    for (final ConversationMessage message in messages) {
      if (message.kind != 'message') {
        continue;
      }
      final String content = resolveContentWithSpeaker(
        message: message,
        prefixSpeaker: prefixSpeaker,
        speakerNameResolver: speakerNameResolver,
      );
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
