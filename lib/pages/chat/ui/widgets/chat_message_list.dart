import 'dart:math' as math;
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
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              GestureDetector(
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
              // 仅对方（左侧）气泡显示悬浮朗读球，半溢出左上角。
              if (!isUser && ttsEnabled && message.text.trim().isNotEmpty)
                Positioned(
                  top: -8,
                  left: -8,
                  child: _MessagePlayButton(
                    text: message.text,
                    globalSeed: ttsGlobalSeed,
                    voiceSeedForTa: voiceSeedForTa,
                    speakerTaId: message.speakerTaId,
                    quoteOnly: ttsQuoteOnly,
                  ),
                ),
            ],
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
  _MessagePlayButton({
    required this.text,
    this.globalSeed,
    this.voiceSeedForTa,
    this.speakerTaId,
    this.quoteOnly = true,
  }) : super(key: Key('tts_play_$speakerTaId'));

  final String text;
  final int? globalSeed;
  final VoiceSeedForTa? voiceSeedForTa;
  final String? speakerTaId;
  final bool quoteOnly;

  @override
  State<_MessagePlayButton> createState() => _MessagePlayButtonState();
}

class _MessagePlayButtonState extends State<_MessagePlayButton>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  bool _playing = false;
  String _status = '';

  /// 播放中「正在朗读」的波形动画。
  late final AnimationController _waveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    // 监听全局播放状态：当前播放被停止或自然播完时，复位本按钮的播放中状态。
    TtsPlayer.instance.playing.addListener(_onTtsPlayingChanged);
  }

  @override
  void dispose() {
    TtsPlayer.instance.playing.removeListener(_onTtsPlayingChanged);
    _waveCtrl.dispose();
    super.dispose();
  }

  void _onTtsPlayingChanged() {
    if (!mounted) return;
    if (!TtsPlayer.instance.playing.value && _playing) {
      _stopWave();
      setState(() {
        _playing = false;
        _status = '';
      });
    }
  }

  void _startWave() {
    if (!_waveCtrl.isAnimating) {
      _waveCtrl.repeat(reverse: true);
    }
  }

  void _stopWave() {
    if (_waveCtrl.isAnimating) {
      _waveCtrl.stop();
      _waveCtrl.value = 0;
    }
  }

  Future<void> _play() async {
    if (_busy || _playing) return;
    setState(() {
      _busy = true;
      _playing = false;
      _status = '0%';
    });
    // 让进度先渲染一帧（引擎同步推理在后台 isolate，不阻塞 UI）
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 点击时重新读取最新角色 seed：角色的 voiceSeed 是异步加载的，
    // build 时可能还是 null（退回 globalSeed），导致两次点击缓存 key 不同、
    // 重复合成。这里直接取当前最新值，保证这一次合成用的 key 与后续一致。
    final int? roleSeed = widget.voiceSeedForTa?.call(widget.speakerTaId);
    try {
      final Float32List wav = await TtsService.instance.synthesize(
        widget.text,
        roleSeed: roleSeed,
        globalSeed: widget.globalSeed,
        quoteOnly: widget.quoteOnly,
        onProgress: (double p) {
          if (!mounted) return;
          setState(() => _status = '${(p * 100).round()}%');
        },
      );
      // 即使本 Widget 已被卸载（列表重建）也照常播放，避免第一次合成的
      // 结果被 `!mounted` 丢弃而需要再点一次才出声。
      if (!mounted) {
        await TtsPlayer.instance.play(wav);
        return;
      }
      setState(() {
        _busy = false;
        _playing = true;
        _status = '';
      });
      _startWave();
      await TtsPlayer.instance.play(wav);
      // 播放自然结束/被其它播放停止时，由 TtsPlayer.playing 监听统一复位。
    } catch (e) {
      if (!mounted) return;
      _stopWave();
      setState(() {
        _busy = false;
        _playing = false;
        _status = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('语音合成失败：$e')),
      );
    }
  }

  Future<void> _stop() async {
    _stopWave();
    await TtsPlayer.instance.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _status = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fg = cs.onPrimaryContainer;
    // 播放中：显示「正在朗读」的波形动画球 + 独立停止按钮。
    if (_playing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: '正在朗读',
            child: Material(
              color: cs.primaryContainer.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              elevation: 2,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Center(child: _buildPlayingFace(fg)),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Tooltip(
            message: '停止',
            child: Material(
              color: cs.primaryContainer.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _stop,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: Center(child: Icon(Icons.stop, size: 14)),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // 空闲 / 合成中：单个悬浮球。
    return Tooltip(
      message: '朗读',
      child: Material(
        color: cs.primaryContainer.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _busy ? null : _play,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Center(child: _buildFace(cs, fg)),
          ),
        ),
      ),
    );
  }

  /// 悬浮球内部内容：空闲显示播放图标；合成中显示百分比数字。
  Widget _buildFace(ColorScheme cs, Color fg) {
    if (!_busy) {
      return Icon(Icons.play_arrow, size: 16, color: fg);
    }
    return Text(
      _status.replaceAll('%', ''),
      style: TextStyle(
        fontSize: 8.5,
        height: 1,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
    );
  }

  /// 播放中的波形动画：三根跳动的竖条，直观表示「正在朗读」。
  Widget _buildPlayingFace(Color fg) {
    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (BuildContext context, Widget? _) {
        final double t = _waveCtrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List<Widget>.generate(3, (int i) {
            final double h =
                6 + 7 * (0.5 + 0.5 * math.sin(t * 2 * math.pi - i * 1.4));
            return Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: fg,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
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
