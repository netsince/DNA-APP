import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../models/conversation.dart';
import '../../../../services/tts/tts_player.dart';
import '../../../../services/tts/tts_service.dart';
import '../../chat_models.dart';
import 'package:dna/widgets/fit_text.dart';

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

/// 解析角色固定语音 seed：返回对应 TA 的 voiceSeed（无则 null）。
typedef VoiceSeedForTa = int? Function(String? taId);

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
    this.ttsEnabled = false,
    this.ttsGlobalSeed,
    this.voiceSeedForTa,
    this.ttsQuoteOnly = true,
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

  /// 是否启用端侧语音合成（AppSettings.ttsEnabled）。
  final bool ttsEnabled;

  /// 全局 TTS seed（角色未设 seed 时兜底）。
  final int? ttsGlobalSeed;

  /// 解析角色固定 seed：根据 speakerTaId 返回对应 TA 的 voiceSeed（无则 null）。
  final VoiceSeedForTa? voiceSeedForTa;

  /// 合成时是否「引号内容优先」（AppSettings.ttsQuoteOnly）。
  final bool ttsQuoteOnly;

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
                        FitText('建议生成摘要'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: summaryInProgress ? null : () => onStartSummary(message),
                          child: const FitText('生成摘要'),
                        ),
                        OutlinedButton(
                          onPressed: () => onDismissSummary(message.id),
                          child: const FitText('忽略'),
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
                        FitText('摘要已生成'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FitText(preview, style: textTheme.bodySmall),
                    const SizedBox(height: 4),
                    FitText(
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
                  if (!isUser && ttsEnabled && message.text.trim().isNotEmpty) ...<Widget>[
                    _MessagePlayButton(
                      text: message.text,
                      roleSeed: voiceSeedForTa?.call(message.speakerTaId),
                      globalSeed: ttsGlobalSeed,
                      quoteOnly: ttsQuoteOnly,
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (speakerName != null && speakerName.isNotEmpty) ...<Widget>[
                    FitText(
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
                              FitText(
                                '思考内容',
                                style: textTheme.labelSmall?.copyWith(color: colorScheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FitText(thoughtText, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                  if (message.text.isNotEmpty && showTokenCounts) ...<Widget>[
                    const SizedBox(height: 6),
                    FitText(
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

/// 对方气泡左上角的语音合成播放按钮。
///
/// 点击 → 合成（显示百分比）→ 自动播放；合成结果经 TtsAudioCache 去重，
/// 已合成过的内容再次点击会命中缓存直接重播。
class _MessagePlayButton extends StatefulWidget {
  const _MessagePlayButton({
    required this.text,
    this.roleSeed,
    this.globalSeed,
    this.quoteOnly = true,
  });

  final String text;
  final int? roleSeed;
  final int? globalSeed;
  final bool quoteOnly;

  @override
  State<_MessagePlayButton> createState() => _MessagePlayButtonState();
}

class _MessagePlayButtonState extends State<_MessagePlayButton> {
  bool _busy = false;
  String _status = '';

  Future<void> _play() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '0%';
    });
    // 让进度先渲染一帧（引擎同步推理在后台 isolate，不阻塞 UI）
    await Future<void>.delayed(const Duration(milliseconds: 60));
    try {
      final Float32List wav = await TtsService.instance.synthesize(
        widget.text,
        roleSeed: widget.roleSeed,
        globalSeed: widget.globalSeed,
        quoteOnly: widget.quoteOnly,
        onProgress: (double p) {
          if (!mounted) return;
          setState(() => _status = '${(p * 100).round()}%');
        },
      );
      if (!mounted) return;
      setState(() => _status = '播放中…');
      await TtsPlayer.instance.play(wav);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('语音合成失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: _busy ? null : _play,
          icon: Icon(
            _busy ? Icons.hourglass_top : Icons.play_circle_outline,
            color: cs.primary,
          ),
          tooltip: '朗读',
        ),
        if (_busy && _status.isNotEmpty)
          FitText(_status, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

TextSpan _buildHighlightedText(BuildContext context, String text, String query, Color highlightColor) {
  final TextStyle base = DefaultTextStyle.of(context).style;
  final ColorScheme colorScheme = Theme.of(context).colorScheme;
  final TextStyle grayStyle = base.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6));

  // Check if a character is an opening bracket (English or Chinese)
  bool isOpeningBracket(String char) {
    return char == '(' || char == '（';
  }

  // Check if a character is a closing bracket (English or Chinese)
  bool isClosingBracket(String char) {
    return char == ')' || char == '）';
  }

  // Build spans with parenthesis coloring (supports both English and Chinese brackets)
  List<InlineSpan> buildParenthesisSpans(String input, TextStyle normalStyle, TextStyle parenStyle) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int i = 0;
    while (i < input.length) {
      // Find the next opening bracket
      int openIndex = -1;
      for (int j = i; j < input.length; j++) {
        if (isOpeningBracket(input[j])) {
          openIndex = j;
          break;
        }
      }

      if (openIndex == -1) {
        spans.add(TextSpan(text: input.substring(i), style: normalStyle));
        break;
      }

      // Add text before opening bracket
      if (openIndex > i) {
        spans.add(TextSpan(text: input.substring(i, openIndex), style: normalStyle));
      }

      // Find matching closing bracket
      int closeIndex = openIndex + 1;
      int depth = 1;
      while (closeIndex < input.length && depth > 0) {
        if (isOpeningBracket(input[closeIndex])) {
          depth++;
        } else if (isClosingBracket(input[closeIndex])) {
          depth--;
        }
        closeIndex++;
      }

      if (depth == 0) {
        // Found matching closing bracket, add the bracket content with gray style
        spans.add(TextSpan(text: input.substring(openIndex, closeIndex), style: parenStyle));
        i = closeIndex;
      } else {
        // No matching closing bracket, add the rest as normal
        spans.add(TextSpan(text: input.substring(openIndex), style: normalStyle));
        break;
      }
    }
    return spans;
  }

  if (query.isEmpty) {
    return TextSpan(children: buildParenthesisSpans(text, base, grayStyle));
  }

  final String lowerText = text.toLowerCase();
  final String lowerQuery = query.toLowerCase();
  int start = 0;
  final List<InlineSpan> spans = <InlineSpan>[];
  while (true) {
    final int index = lowerText.indexOf(lowerQuery, start);
    if (index == -1) {
      spans.addAll(buildParenthesisSpans(text.substring(start), base, grayStyle));
      break;
    }
    if (index > start) {
      spans.addAll(buildParenthesisSpans(text.substring(start, index), base, grayStyle));
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
