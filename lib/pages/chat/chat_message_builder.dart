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
    String? authorNote,
    int authorNoteInterval = 0,
    String? loreText,
  }) {
    // 缓存友好布局：静态 system prompt 在前，摘要随后，历史按追加顺序排列，
    // 动态内容（Lorebook 词条、Author's Note）统一放在历史之后。
    // 这样 system + 摘要 + 历史的组合前缀保持稳定，最大化 KV cache 命中。
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
      payload.add(<String, String>{'role': message.role, 'content': content});
    }
    // 动态尾部：Lorebook 激活词条（按需注入，不污染前缀）。
    if (loreText != null && loreText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': loreText.trim()});
    }
    // 动态尾部：作者注释 Author's Note。interval > 0 时以固定位置注入，
    // 避免深度注入导致历史中部前缀不稳定。
    if (authorNote != null &&
        authorNote.trim().isNotEmpty &&
        authorNoteInterval > 0) {
      payload.add(<String, String>{'role': 'system', 'content': authorNote.trim()});
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }

  /// 生成 Lorebook 动态尾部的 system 消息（为空返回 null）。
  /// 供 [buildMessagesFrom] 与手工组装 payload 的入口（如"继续"）复用。
  static Map<String, String>? loreSystemMessage(String loreText) {
    if (loreText.trim().isEmpty) {
      return null;
    }
    return <String, String>{'role': 'system', 'content': loreText.trim()};
  }
}
