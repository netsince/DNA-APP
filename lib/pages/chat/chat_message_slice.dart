import '../../models/conversation.dart';
import 'chat_models.dart';
import 'chat_token_counter.dart';

class ChatMessageSlice {
  static ConversationSummary? latestSummary(Conversation conversation) {
    if (conversation.summaries.isEmpty) {
      return null;
    }
    return conversation.summaries.last;
  }

  static int summaryEndIndex(Conversation conversation) {
    final ConversationSummary? summary = latestSummary(conversation);
    if (summary == null || summary.endMessageId.isEmpty) {
      return -1;
    }
    return conversation.messages
        .indexWhere((ConversationMessage m) => m.id == summary.endMessageId);
  }

  static MessageSlice sliceForPayload(
    Conversation conversation, {
    int? endExclusive,
    Set<String>? excludeIds,
    int? maxMessages,
    int? maxTokens,
    ChatTokenCounter? tokenCounter,
    String? tokenModel,
  }) {
    final int summaryEnd = summaryEndIndex(conversation);
    final int total = conversation.messages.length;
    final int end = endExclusive == null ? total : endExclusive.clamp(0, total);
    final bool includeSummary = summaryEnd >= 0 && end > summaryEnd;
    final int start = includeSummary ? summaryEnd + 1 : 0;
    List<ConversationMessage> slice = conversation.messages
        .sublist(start, end)
        .where((ConversationMessage m) => m.kind == 'message')
        .where((ConversationMessage m) => excludeIds == null || !excludeIds.contains(m.id))
        .toList();
    // 上下文预算：仅保留最近 [maxMessages] 条消息，防止长对话超出模型窗口导致退化。
    if (maxMessages != null && maxMessages > 0 && slice.length > maxMessages) {
      slice = slice.sublist(slice.length - maxMessages);
    }
    // 精确 token 预算：用当前模型 tokenizer，从最新往最老逐条累积 token，
    // 超出 [maxTokens] 即裁掉更早的消息。0 表示不限制。
    if (maxTokens != null && maxTokens > 0 && tokenCounter != null) {
      int budget = 0;
      int keepFrom = slice.length; // 保留 [keepFrom, len)
      for (int i = slice.length - 1; i >= 0; i--) {
        final int t = tokenCounter.countTokens(
          model: tokenModel ?? '',
          messageId: slice[i].id,
          text: slice[i].text,
        );
        if (budget + t > maxTokens) {
          break;
        }
        budget += t;
        keepFrom = i;
      }
      if (keepFrom > 0) {
        slice = slice.sublist(keepFrom);
      }
    }
    return MessageSlice(messages: slice, includeSummary: includeSummary);
  }
}
