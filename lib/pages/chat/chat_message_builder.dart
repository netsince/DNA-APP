import '../../models/conversation.dart';
import '../../models/world.dart';
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
    List<WorldEntry>? activeEntries,
  }) {
    // 注：世界词条（Lorebook）已由 ChatSystemPrompt.build 注入到 systemPrompt 顶部，
    // 此处无需重复插入，activeEntries 仅用于保持调用方接口一致。
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
    final List<Map<String, String>> history = <Map<String, String>>[];
    for (final ConversationMessage message in messages) {
      if (message.kind != 'message') {
        continue;
      }
      final String content = resolveContentWithSpeaker(
        message: message,
        prefixSpeaker: prefixSpeaker,
        speakerNameResolver: speakerNameResolver,
      );
      history.add(<String, String>{'role': message.role, 'content': content});
    }
    // 深度注入（作者注释 Author's Note）：每隔 authorNoteInterval 条历史消息，
    // 在对话中间插入一段提示，而不只是放在 system 开头。
    if (authorNote != null &&
        authorNote.trim().isNotEmpty &&
        authorNoteInterval > 0 &&
        history.isNotEmpty) {
      final String note = authorNote.trim();
      final List<Map<String, String>> withNotes = <Map<String, String>>[];
      for (int i = 0; i < history.length; i++) {
        withNotes.add(history[i]);
        final int fromEnd = history.length - 1 - i;
        if (fromEnd > 0 && fromEnd % authorNoteInterval == 0) {
          withNotes.add(<String, String>{'role': 'system', 'content': note});
        }
      }
      payload.addAll(withNotes);
    } else {
      payload.addAll(history);
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }
}
