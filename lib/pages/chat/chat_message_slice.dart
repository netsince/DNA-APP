import '../../models/conversation.dart';
import '../../models/message_attachment.dart';
import 'chat_models.dart';
import 'chat_token_counter.dart';

/// 单张图片在上下文预算里的粗略 token 折算（视觉模型的真实计费因模型而异）。
const int kImageTokenEstimate = 1000;

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
    String? summaryText,
  }) {
    final int summaryEnd = summaryEndIndex(conversation);
    final int total = conversation.messages.length;
    final int end = endExclusive == null ? total : endExclusive.clamp(0, total);
    final bool includeSummary = summaryEnd >= 0 && end > summaryEnd;
    final int start = includeSummary ? summaryEnd + 1 : 0;
    List<ConversationMessage> slice = conversation.messages
        .sublist(start, end)
        .where((ConversationMessage m) => m.kindEnum == MessageKind.message)
        .where((ConversationMessage m) => excludeIds == null || !excludeIds.contains(m.id))
        .toList();
    // 上下文预算：仅保留最近 [maxMessages] 条消息，防止长对话超出模型窗口导致退化。
    if (maxMessages != null && maxMessages > 0 && slice.length > maxMessages) {
      slice = slice.sublist(slice.length - maxMessages);
    }
    // 精确 token 预算：用当前模型 tokenizer，从最新往最老逐条累积 token，
    // 超出 [maxTokens] 即裁掉更早的消息。0 表示不限制。
    if (maxTokens != null && maxTokens > 0 && tokenCounter != null) {
      // 摘要文本同样占用上下文预算：先扣除，再对历史消息裁剪，
      // 避免长摘要持续挤占预算，导致上下文几乎只剩摘要。
      int budget = 0;
      if (includeSummary && summaryText != null && summaryText.trim().isNotEmpty) {
        budget += tokenCounter.countTokens(
          model: tokenModel ?? '',
          messageId: '__summary__',
          text: summaryText,
        );
      }
      int keepFrom = slice.length; // 保留 [keepFrom, len)
      for (int i = slice.length - 1; i >= 0; i--) {
        final int t = _estimateMessageTokens(
          tokenCounter: tokenCounter,
          tokenModel: tokenModel ?? '',
          message: slice[i],
        );
        if (budget + t > maxTokens) {
          break;
        }
        budget += t;
        keepFrom = i;
      }
      // 兜底：**最新一条消息永远保留**。
      //
      // 否则「一条消息就超预算」时（大文件附件、粘贴了几万字），整轮上下文
      // 会被裁成空 —— 用户发了一句话，模型却连这句话都没收到，只看到错误。
      // 这条保证之后，超预算的后果退化成「模型上下文被截断」，而不是「失联」。
      if (keepFrom >= slice.length && slice.isNotEmpty) {
        keepFrom = slice.length - 1;
      }
      if (keepFrom > 0) {
        slice = slice.sublist(keepFrom);
      }
    }
    return MessageSlice(messages: slice, includeSummary: includeSummary);
  }

  /// 估算一条消息实际会占多少 token。
  ///
  /// **不能只算 `message.text`**：文本附件会把几千字正文塞进请求，图片虽然
  /// 不占文本 token，但视觉模型按图计费。不把它们算进来的话，用户丢一个
  /// 大文件进来，预算看起来还很空，请求却直接 400（超上下文）。
  ///
  /// 图片按每张 [kImageTokenEstimate] 粗估：不同模型差异大，这里取保守值，
  /// 宁可少留一点余量，也不要卡着上限去撞 400。
  static int _estimateMessageTokens({
    required ChatTokenCounter tokenCounter,
    required String tokenModel,
    required ConversationMessage message,
  }) {
    int tokens = tokenCounter.countTokens(
      model: tokenModel,
      messageId: message.id,
      text: message.text,
    );
    if (message.attachments.isEmpty) return tokens;
    int images = 0;
    for (final MessageAttachment a in message.attachments) {
      if (a.isImage) {
        images++;
        continue;
      }
      final String? preview = a.textPreview;
      if (preview == null || preview.isEmpty) continue;
      tokens += tokenCounter.countTokens(
        model: tokenModel,
        messageId: '${message.id}#${a.hashCode}',
        text: preview,
      );
    }
    return tokens + images * kImageTokenEstimate;
  }
}
