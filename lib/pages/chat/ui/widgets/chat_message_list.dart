import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../models/conversation.dart';
import '../../../../services/tts/tts_player.dart';
import '../../../../services/tts/tts_service.dart';
import '../../../../utils/light_markdown.dart';
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

/// 解析角色头像：返回对应 TA 的头像（无则 null）。
typedef AvatarForTa = ImageProvider? Function(String? taId);

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
    this.showMessageAvatar = true,
    this.showMessageRetry = true,
    this.showMessageCopy = true,
    this.showMessageContinue = true,
    this.avatarForMessage,
    this.onRetryMessage,
    this.onCopyMessage,
    this.onContinueMessage,
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

  /// 是否显示对方消息头像（AppSettings.showMessageAvatar）。
  final bool showMessageAvatar;

  /// 是否显示对方消息「重说」快捷按钮（AppSettings.showMessageRetry）。
  final bool showMessageRetry;

  /// 是否显示对方消息「复制」快捷按钮（AppSettings.showMessageCopy）。
  final bool showMessageCopy;

  /// 是否显示对方消息「继续说」快捷按钮（AppSettings.showMessageContinue）。
  final bool showMessageContinue;

  /// 解析消息作者头像：根据 speakerTaId 返回头像（无则 null）。
  final AvatarForTa? avatarForMessage;

  /// 点击「重说」回调（仅最近一条 AI 消息可用）。
  final VoidCallback? onRetryMessage;

  /// 点击「复制」回调。
  final void Function(String text)? onCopyMessage;

  /// 点击「继续说」回调（仅最近一条 AI 消息可用）。
  final VoidCallback? onContinueMessage;

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
        // 是否为最近一条 AI 消息：用于控制「重说/继续说」快捷按钮的显示。
        final bool isLastAssistant = !isUser &&
            message.kind == 'message' &&
            index == conversation.messages.lastIndexWhere(
              (ConversationMessage m) => m.kind == 'message' && m.role == 'assistant',
            );
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
              // 仅对方（左侧）气泡显示悬浮操作区，半溢出左上角：
              // 头像（可选）+ 朗读球；右上角为「重说/复制/继续说」快捷按钮（可选）。
              if (!isUser && message.kind == 'message' && message.text.trim().isNotEmpty) ...<Widget>[
                Positioned(
                  top: -8,
                  left: -8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showMessageAvatar && avatarForMessage != null) ...<Widget>[
                        _MessageAvatarButton(
                          avatar: avatarForMessage!(message.speakerTaId),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (ttsEnabled)
                        _MessagePlayButton(
                          text: message.text,
                          globalSeed: ttsGlobalSeed,
                          voiceSeedForTa: voiceSeedForTa,
                          speakerTaId: message.speakerTaId,
                          quoteOnly: ttsQuoteOnly,
                        ),
                    ],
                  ),
                ),
                if ((showMessageRetry && isLastAssistant) ||
                    (showMessageCopy) ||
                    (showMessageContinue && isLastAssistant)) ...<Widget>[
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (showMessageCopy)
                          _MessageActionButton(
                            tooltip: '复制',
                            icon: Icons.copy_rounded,
                            onTap: onCopyMessage == null
                                ? null
                                : () => onCopyMessage!(message.text),
                          ),
                        if (showMessageRetry && isLastAssistant)
                          _MessageActionButton(
                            tooltip: '重说',
                            icon: Icons.refresh_rounded,
                            onTap: isLastAssistant ? onRetryMessage : null,
                          ),
                        if (showMessageContinue && isLastAssistant)
                          _MessageActionButton(
                            tooltip: '继续说',
                            icon: Icons.play_arrow_rounded,
                            onTap: isLastAssistant ? onContinueMessage : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 对方气泡左上角的角色头像圆钮，样式与 TTS 朗读球一致（26x26 圆形）。
class _MessageAvatarButton extends StatelessWidget {
  const _MessageAvatarButton({required this.avatar});

  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 26,
        height: 26,
        child: avatar == null
            ? Icon(Icons.person, size: 16, color: cs.onPrimaryContainer)
            : Image(image: avatar!, fit: BoxFit.cover),
      ),
    );
  }
}

/// 对方气泡右上角的轻量操作按钮（重说/复制/继续说）。
class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.tooltip,
    required this.icon,
    this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Widget child = Material(
      color: cs.secondaryContainer.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 15, color: cs.onSecondaryContainer),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: onTap == null ? child : Tooltip(message: tooltip, child: child),
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

class _MessagePlayButtonState extends State<_MessagePlayButton> {
  bool _busy = false;
  bool _playing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // 监听全局播放状态：当前播放被停止或自然播完时，复位本按钮的播放中状态。
    TtsPlayer.instance.playing.addListener(_onTtsPlayingChanged);
  }

  @override
  void dispose() {
    TtsPlayer.instance.playing.removeListener(_onTtsPlayingChanged);
    super.dispose();
  }

  void _onTtsPlayingChanged() {
    if (!mounted) return;
    if (!TtsPlayer.instance.playing.value && _playing) {
      setState(() {
        _playing = false;
        _status = '';
      });
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
      await TtsPlayer.instance.play(wav);
      // 播放自然结束/被其它播放停止时，由 TtsPlayer.playing 监听统一复位。
    } catch (e) {
      if (!mounted) return;
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
    // 单个切换按钮：空闲→播放；播放中→暂停（点击停止）；合成中→百分比（禁用）。
    final String message = _busy
        ? '合成中'
        : (_playing ? '停止朗读' : '朗读');
    final VoidCallback? onTap = _busy
        ? null
        : (_playing ? _stop : _play);
    return Tooltip(
      message: message,
      child: Material(
        color: cs.primaryContainer.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Center(child: _buildFace(cs, fg)),
          ),
        ),
      ),
    );
  }

  /// 悬浮球内部内容：空闲显示播放图标；播放中显示暂停图标；合成中显示百分比数字。
  Widget _buildFace(ColorScheme cs, Color fg) {
    if (_busy) {
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
    if (_playing) {
      return Icon(Icons.pause, size: 16, color: fg);
    }
    return Icon(Icons.play_arrow, size: 16, color: fg);
  }
}

TextSpan _buildHighlightedText(BuildContext context, String text, String query, Color highlightColor) {
  final TextStyle base = DefaultTextStyle.of(context).style;
  final ColorScheme colorScheme = Theme.of(context).colorScheme;

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

      if (openIndex > i) {
        spans.add(TextSpan(text: input.substring(i, openIndex), style: normalStyle));
      }

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
        spans.add(TextSpan(text: input.substring(openIndex, closeIndex), style: parenStyle));
        i = closeIndex;
      } else {
        spans.add(TextSpan(text: input.substring(openIndex), style: normalStyle));
        break;
      }
    }
    return spans;
  }

  // 对一段纯文本应用「括号灰色」+「搜索高亮」，返回内联片段。
  List<InlineSpan> buildPlainSpans(String input, TextStyle style) {
    final TextStyle grayStyle = style.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6));
    if (query.isEmpty) {
      return buildParenthesisSpans(input, style, grayStyle);
    }
    final String lowerText = input.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    int start = 0;
    final List<InlineSpan> spans = <InlineSpan>[];
    while (true) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.addAll(buildParenthesisSpans(input.substring(start), style, grayStyle));
        break;
      }
      if (index > start) {
        spans.addAll(buildParenthesisSpans(input.substring(start, index), style, grayStyle));
      }
      spans.add(
        TextSpan(
          text: input.substring(index, index + query.length),
          style: style.copyWith(backgroundColor: highlightColor),
        ),
      );
      start = index + query.length;
    }
    return spans;
  }

  final TextStyle codeStyle = base.copyWith(
    fontFamily: 'monospace',
    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
    fontSize: (base.fontSize ?? 14) * 0.92,
  );

  // 依据轻量 Markdown 标记生成带样式的片段，并在此基础上叠加括号/搜索高亮。
  final List<InlineSpan> children = <InlineSpan>[];
  for (final LightMarkdownRun run in parseLightMarkdown(text)) {
    TextStyle style = base;
    if (run.code) {
      style = codeStyle;
    } else {
      if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
      if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (run.strike) style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    children.addAll(buildPlainSpans(run.text, style));
  }
  return TextSpan(children: children, style: base);
}
