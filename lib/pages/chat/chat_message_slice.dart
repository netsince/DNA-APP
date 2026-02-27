import '../../models/conversation.dart';
import 'chat_models.dart';

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
  }) {
    final int summaryEnd = summaryEndIndex(conversation);
    final int total = conversation.messages.length;
    final int end = endExclusive == null ? total : endExclusive.clamp(0, total);
    final bool includeSummary = summaryEnd >= 0 && end > summaryEnd;
    final int start = includeSummary ? summaryEnd + 1 : 0;
    final List<ConversationMessage> slice = conversation.messages
        .sublist(start, end)
        .where((ConversationMessage m) => m.kind == 'message')
        .where((ConversationMessage m) => excludeIds == null || !excludeIds.contains(m.id))
        .toList();
    return MessageSlice(messages: slice, includeSummary: includeSummary);
  }
}
