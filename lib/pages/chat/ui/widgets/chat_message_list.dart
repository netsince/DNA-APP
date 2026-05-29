import 'package:flutter/material.dart';

import '../../../../models/conversation.dart';
import '../../chat_models.dart';

typedef ShowMessageMenu = void Function({
  required Offset position,
  required ConversationMessage message,
  required int index,
});

typedef TokenCountForMessage = int Function(String messageId, String text);

typedef SummaryById = ConversationSummary? Function(String? id);

typedef MessageAction = Future<void> Function(ConversationMessage message);

typedef MessageIdAction = Future<void> Function(String messageId);

typedef TaNameForId = String? Function(String? taId);

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.conversation,
    required this.scrollController,
    required this.messageKeys,
    required this.userBubble,
    required this.assistantBubble,
    required this.showTokenCounts,
    required this.searchQuery,
    required this.thoughtsByMessageId,
    required this.tokenCountForMessage,
    required this.summaryById,
    required this.onStartSummary,
    required this.onDismissSummary,
    required this.onShowMessageMenu,
    required this.summaryInProgress,
    required this.showSpeakerLabels,
    required this.taNameForId,
    required this.visibleThoughtMessageIds,
  });

  final Conversation conversation;
  final ScrollController scrollController;
  final Map<String, GlobalKey> messageKeys;
  final Color userBubble;
  final Color assistantBubble;
  final bool showTokenCounts;
  final String searchQuery;
  final Map<String, ThoughtEntry> thoughtsByMessageId;
  final TokenCountForMessage tokenCountForMessage;
  final SummaryById summaryById;
  final MessageAction onStartSummary;
  final MessageIdAction onDismissSummary;
  final ShowMessageMenu onShowMessageMenu;
  final bool summaryInProgress;
  final bool showSpeakerLabels;
  final TaNameForId taNameForId;
  final Set<String> visibleThoughtMessageIds;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: conversation.messages.length,
      itemBuilder: (BuildContext context, int index) {
        final ConversationMessage message = conversation.messages[index];
        messageKeys.putIfAbsent(message.id, () => GlobalKey(debugLabel: message.id));
        final GlobalKey? key = messageKeys[message.id];

        if (message.kind == 'summary_prompt') {
          return Align(
            key: key,
            alignment: Alignment.center,
            child: GestureDetector(
              onLongPressStart: (LongPressStartDetails details) {
                onShowMessageMenu(
                  position: details.globalPosition,
                  message: message,
                  index: index,
                );
              },
              onSecondaryTapDown: (TapDownDetails details) {
                onShowMessageMenu(
                  position: details.globalPosition,
                  message: message,
                  index: index,
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.auto_awesome, size: 18),
                        SizedBox(width: 6),
                        Text('建议生成摘要'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: summaryInProgress ? null : () => onStartSummary(message),
                          child: const Text('生成摘要'),
                        ),
                        OutlinedButton(
                          onPressed: () => onDismissSummary(message.id),
                          child: const Text('忽略'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (message.kind == 'summary') {
          final ConversationSummary? summary = summaryById(message.summaryId);
          final String raw = summary?.text.trim() ?? '';
          final String preview =
              raw.isEmpty ? '摘要为空' : (raw.length > 80 ? '${raw.substring(0, 80)}...' : raw);
          return Align(
            key: key,
            alignment: Alignment.center,
            child: GestureDetector(
              onLongPressStart: (LongPressStartDetails details) {
                onShowMessageMenu(
                  position: details.globalPosition,
                  message: message,
                  index: index,
                );
              },
              onSecondaryTapDown: (TapDownDetails details) {
                onShowMessageMenu(
                  position: details.globalPosition,
                  message: message,
                  index: index,
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.article_outlined, size: 18),
                        SizedBox(width: 6),
                        Text('摘要已生成'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(preview, style: textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      '长按/右键查看/删除',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final bool isUser = message.role == 'user';
        final Alignment alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final Color bubbleColor = isUser ? userBubble : assistantBubble;
        final int charCount = message.text.runes.length;
        final int tokenCount = showTokenCounts ? tokenCountForMessage(message.id, message.text) : 0;
        final String thoughtText = thoughtsByMessageId[message.id]?.text.trim() ?? '';
        final String? speakerName = (!isUser && showSpeakerLabels)
            ? taNameForId(message.speakerTaId)?.trim()
            : null;

        return Align(
          key: key,
          alignment: alignment,
          child: GestureDetector(
            onLongPressStart: (LongPressStartDetails details) {
              onShowMessageMenu(
                position: details.globalPosition,
                message: message,
                index: index,
              );
            },
            onSecondaryTapDown: (TapDownDetails details) {
              onShowMessageMenu(
                position: details.globalPosition,
                message: message,
                index: index,
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (speakerName != null && speakerName.isNotEmpty) ...<Widget>[
                    Text(
                      speakerName,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  RichText(
                    text: _buildHighlightedText(
                      context,
                      message.text,
                      searchQuery,
                      colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                    ),
                  ),
                  if (thoughtText.isNotEmpty && visibleThoughtMessageIds.contains(message.id)) ...<Widget>[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.psychology_outlined, size: 14, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                '思考内容',
                                style: textTheme.labelSmall?.copyWith(color: colorScheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(thoughtText, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                  if (message.text.isNotEmpty && showTokenCounts) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '字数 $charCount / Token $tokenCount',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

TextSpan _buildHighlightedText(BuildContext context, String text, String query, Color highlightColor) {
  final TextStyle base = DefaultTextStyle.of(context).style;
  if (query.isEmpty) {
    return TextSpan(text: text, style: base);
  }
  final String lowerText = text.toLowerCase();
  final String lowerQuery = query.toLowerCase();
  int start = 0;
  final List<InlineSpan> spans = <InlineSpan>[];
  while (true) {
    final int index = lowerText.indexOf(lowerQuery, start);
    if (index == -1) {
      spans.add(TextSpan(text: text.substring(start), style: base));
      break;
    }
    if (index > start) {
      spans.add(TextSpan(text: text.substring(start, index), style: base));
    }
    spans.add(
      TextSpan(
        text: text.substring(index, index + query.length),
        style: base.copyWith(backgroundColor: highlightColor),
      ),
    );
    start = index + query.length;
  }
  return TextSpan(children: spans, style: base);
}
