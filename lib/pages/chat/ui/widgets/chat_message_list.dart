import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../../../models/conversation.dart';
import '../../../../models/message_attachment.dart';
import '../../../../services/attachment_storage.dart';
import '../../../../utils/ui_feedback.dart';
import '../../../../services/tts/tts_player.dart';
import '../../../../services/tts/tts_service.dart';
import '../../../../utils/novel_text_spans.dart';
import '../../../../utils/platform_capabilities.dart';
import '../../chat_models.dart';
import 'package:dna/widgets/fit_text.dart';

import 'message_bubbles.dart';

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
    this.streamErrors = const <String, String>{},
    this.onRetryFailed,
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

  /// 生成失败的消息 id → 失败原因。
  ///
  /// 失败态由聊天页的流处理器登记（见 chat_stream_handlers 的 _streamErrors），
  /// 这里把它渲染成气泡下方的行内错误条：失败必须留在列表里可见，
  /// 不能只靠一条 snackbar（审计 3.5）。
  final Map<String, String> streamErrors;

  /// 行内「重试」回调（复用现有的重说动作）。
  final VoidCallback? onRetryFailed;

  @override
  Widget build(BuildContext context) {

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: conversation.messages.length,
      itemBuilder: (BuildContext context, int index) {
        final ConversationMessage message = conversation.messages[index];
        messageKeys.putIfAbsent(message.id, () => GlobalKey(debugLabel: message.id));
        final GlobalKey? key = messageKeys[message.id];

        if (message.kindEnum == MessageKind.summaryPrompt) {
          return SummaryPromptBubble(
            key: key,
            message: message,
            index: index,
            summaryInProgress: summaryInProgress,
            onStartSummary: onStartSummary,
            onDismissSummary: onDismissSummary,
            onShowMessageMenu: onShowMessageMenu,
          );
        }

        if (message.kindEnum == MessageKind.summary) {
          return SummaryBubble(
            key: key,
            message: message,
            index: index,
            summaryById: summaryById,
            onShowMessageMenu: onShowMessageMenu,
          );
        }

        final bool isUser = message.role == 'user';
        // 是否为最近一条 AI 消息：用于控制「重说/继续说」快捷按钮的显示。
        final bool isLastAssistant = !isUser &&
            message.kindEnum == MessageKind.message &&
            index == conversation.messages.lastIndexWhere(
              (ConversationMessage m) => m.kindEnum == MessageKind.message && m.role == 'assistant',
            );
        final Color bubbleColor = isUser ? userBubble : assistantBubble;
        final int charCount = message.text.runes.length;
        final int tokenCount = showTokenCounts ? tokenCountForMessage(message.id, message.text) : 0;
        final String thoughtText = thoughtsByMessageId[message.id]?.text.trim() ?? '';
        final String? speakerName = (!isUser && showSpeakerLabels)
            ? taNameForId(message.speakerTaId)?.trim()
            : null;

        // 气泡圆角用令牌（审计 4.4）：主体 AppRadius.lg（20），朝向头像那一角
        // 收小到 AppRadius.xs（8）暗示说话方向 —— 以前手写 20/4。
        final String? streamError = streamErrors[message.id];

        return ChatBubble(
          key: key,
          message: message,
          index: index,
          isUser: isUser,
          isLastAssistant: isLastAssistant,
          bubbleColor: bubbleColor,
          charCount: charCount,
          tokenCount: tokenCount,
          thoughtText: thoughtText,
          speakerName: speakerName,
          searchQuery: searchQuery,
          visibleThoughtMessageIds: visibleThoughtMessageIds,
          showTokenCounts: showTokenCounts,
          showMessageAvatar: showMessageAvatar,
          showMessageCopy: showMessageCopy,
          showMessageRetry: showMessageRetry,
          showMessageContinue: showMessageContinue,
          ttsEnabled: ttsEnabled,
          ttsGlobalSeed: ttsGlobalSeed,
          voiceSeedForTa: voiceSeedForTa,
          ttsQuoteOnly: ttsQuoteOnly,
          avatarForMessage: avatarForMessage,
          streamError: streamError,
          onShowMessageMenu: onShowMessageMenu,
          onCopyMessage: onCopyMessage,
          onRetryMessage: onRetryMessage,
          onContinueMessage: onContinueMessage,
          onRetryFailed: onRetryFailed,
        );
      },
    );
  }
}

/// 生成失败的行内错误条：气泡下方、紧跟该条回复。
///
/// 失败以前只弹一条 snackbar，气泡停在半截后看起来和"生成完了"一样
/// （审计 3.5）。这里把原因与「重试」放在它所属的那条消息下面：
/// - 原因常驻可见，不会随提示条消失；
/// - 「重试」复用现有的重说动作（onRetryFailed），不另造一套重试逻辑；
/// - liveRegion 让读屏在失败出现时主动播报一次。
class _StreamErrorBanner extends StatelessWidget {
  const _StreamErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.xs),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        constraints: const BoxConstraints(maxWidth: AppSize.contentMaxWidth),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: AppSize.iconInline,
              color: cs.onErrorContainer,
            ),
            AppSpacing.wSm,
            Expanded(
              child: FitText(
                message,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  height: AppLineHeight.body,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onErrorContainer,
                  minimumSize: const Size(AppSize.touchTarget, AppSize.touchTarget),
                ),
                child: const FitText('重试'),
              ),
          ],
        ),
      ),
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
      color: cs.primaryContainer.withValues(alpha: AppAlpha.a92),
      shape: const CircleBorder(),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 26,
        height: 26,
        child: avatar == null
            ? Icon(Icons.person, size: 16, color: cs.onPrimaryContainer)
            // 解码尺寸已由 ChatStateMixin 统一限制（按整屏最长边），
            // 这里不再二次包装 ResizeImage —— 套两层会让缓存的 key 与解码路径
            // 都变得难以预期，之前就是这样把气泡头像弄成了破图。
            : Image(
                image: avatar!,
                fit: BoxFit.cover,
                // 加载失败时退回占位图标，不要留一个破图框。
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    Icon(Icons.person, size: 16, color: cs.onPrimaryContainer),
              ),
      ),
    );
  }
}

/// 对方气泡外的轻量操作按钮（朗读/复制/重说/继续说）。
///
/// 命中区按 [AppSize.touchTarget]（48dp）给：以前是 26×26 的自绘圆钮，
/// 视觉尺寸被当成了命中尺寸（审计 4.3「触摸目标 < 48dp」）。这里换成
/// 气泡外那排的**密集控件**：26dp 视觉圆、15dp 图标。
///
/// 刻意不套 48dp —— 48 是「命中盒」不是「视觉尺寸」，而这里一行要排 3-4 颗、
/// 行高由这一行决定。硬抬到 48 会让圆面积涨 240%、气泡被撑高（已回滚一次，
/// 见 docs/REGRESSION_AUDIT.md 与 DESIGN_SPEC 的「密集控件例外」）。
/// tooltip 兼作读屏语义标签（「复制」「重说」「继续说」）。
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
      color: cs.secondaryContainer.withValues(alpha: AppAlpha.a85),
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
      showSnack(context, '语音合成失败：$e');
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
    // Web 端不支持端侧语音合成：整颗按钮置灰、不可点。
    final bool ttsDisabled = !PlatformCapabilities.ttsSupported;
    final Color fg = ttsDisabled ? cs.outline : cs.onPrimaryContainer;
    // 单个切换按钮：空闲→播放；播放中→暂停（点击停止）；合成中→百分比（禁用）。
    final String message = ttsDisabled
        ? '语音合成（当前平台不可用）'
        : (_busy ? '合成中' : (_playing ? '停止朗读' : '朗读'));
    final VoidCallback? onTap = ttsDisabled
        ? null
        : (_busy ? null : (_playing ? _stop : _play));
    // 命中区同样按 48dp 给：朗读球以前也是 26×26 的自绘圆钮（审计 4.3）。
    // 同样是密集控件（26dp 圆，和动作排同高）；tooltip 兼作读屏标签
    // （「朗读／停止朗读／合成中／当前平台不可用」）。
    return Tooltip(
      message: message,
      child: Material(
        color: ttsDisabled
            ? cs.surfaceContainerHighest
            : cs.primaryContainer.withValues(alpha: AppAlpha.a92),
        shape: const CircleBorder(),
        elevation: 1,
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
          fontSize: AppFontSize.tiny,
          height: 1,
          fontWeight: AppWeight.medium,
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


/// 气泡里的附件列表：一行一个，图标 + 名字 + 大小。
///
/// 图片额外给一个缩略图（点开看大图）；文本类只列名字（内容已经进了上下文，
/// 在气泡里再铺一遍反而吵）。
class _MessageAttachments extends StatelessWidget {
  const _MessageAttachments({
    required this.attachments,
    required this.bubbleColor,
  });

  final List<MessageAttachment> attachments;
  final Color bubbleColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color ink = FitText.inkFor(bubbleColor, cs.surface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final MessageAttachment a in attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: AppRadius.xsAll,
              onTap: a.isImage ? () => _openImage(context, a) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: AppRadius.xsAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      a.isImage
                          ? Icons.image_outlined
                          : (a.isText
                              ? Icons.description_outlined
                              : Icons.attach_file_rounded),
                      size: 15,
                      color: ink.withValues(alpha: AppAlpha.a72),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FitText(
                        a.name,
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FitText(
                      a.sizeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ink.withValues(alpha: AppAlpha.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openImage(BuildContext context, MessageAttachment a) async {
    final Uint8List? bytes = await AttachmentStore.instance.read(a.ref);
    if (!context.mounted) return;
    if (bytes == null) {
      showSnack(context, '附件已不在本机（可能被清理或来自其他设备）');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 普通消息气泡（用户 / 对方两种朝向）。
///
/// 从 itemBuilder 里整段搬出来：那个闭包原本三百多行，现在只剩
/// 「算好 7 个派生值 → 派发给气泡」。所有开关与回调都由列表传入，
/// 气泡本身不读 controller，因此可以单独 pump（golden 测试就是这么用的）。
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.index,
    required this.isUser,
    required this.isLastAssistant,
    required this.bubbleColor,
    required this.charCount,
    required this.tokenCount,
    required this.thoughtText,
    required this.speakerName,
    required this.searchQuery,
    required this.visibleThoughtMessageIds,
    required this.showTokenCounts,
    required this.showMessageAvatar,
    required this.showMessageCopy,
    required this.showMessageRetry,
    required this.showMessageContinue,
    required this.ttsEnabled,
    required this.ttsGlobalSeed,
    required this.voiceSeedForTa,
    required this.ttsQuoteOnly,
    required this.avatarForMessage,
    required this.streamError,
    required this.onShowMessageMenu,
    required this.onCopyMessage,
    required this.onRetryMessage,
    required this.onContinueMessage,
    required this.onRetryFailed,
  });

  final ConversationMessage message;
  final int index;
  final bool isUser;
  final bool isLastAssistant;
  final Color bubbleColor;
  final int charCount;
  final int tokenCount;
  final String thoughtText;
  final String? speakerName;
  final String searchQuery;
  final Set<String> visibleThoughtMessageIds;
  final bool showTokenCounts;
  final bool showMessageAvatar;
  final bool showMessageCopy;
  final bool showMessageRetry;
  final bool showMessageContinue;
  final bool ttsEnabled;
  final int? ttsGlobalSeed;
  final VoiceSeedForTa? voiceSeedForTa;
  final bool ttsQuoteOnly;
  final AvatarForTa? avatarForMessage;
  final String? streamError;
  final ShowMessageMenu onShowMessageMenu;
  final void Function(String text)? onCopyMessage;
  final VoidCallback? onRetryMessage;
  final VoidCallback? onContinueMessage;
  final VoidCallback? onRetryFailed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    // 公开字段不能类型提升，取别名给 null 检查用。
    final String? speaker = speakerName;
    final String? errorText = streamError;
            final BorderRadius bubbleRadius = isUser
                ? const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.lg),
                    topRight: Radius.circular(AppRadius.lg),
                    bottomLeft: Radius.circular(AppRadius.lg),
                    bottomRight: Radius.circular(AppRadius.xxs),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.xxs),
                    topRight: Radius.circular(AppRadius.lg),
                    bottomLeft: Radius.circular(AppRadius.lg),
                    bottomRight: Radius.circular(AppRadius.lg),
                  );

            final Widget bubble = GestureDetector(
              onLongPressStart: (LongPressStartDetails details) =>
                  onShowMessageMenu(position: details.globalPosition, message: message, index: index),
              onSecondaryTapDown: (TapDownDetails details) =>
                  onShowMessageMenu(position: details.globalPosition, message: message, index: index),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                constraints: const BoxConstraints(maxWidth: AppSize.contentMaxWidth),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: bubbleRadius,
                  // 阴影走全局唯一来源，不再手写 Colors.black。
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (speaker != null && speaker.isNotEmpty) ...<Widget>[
                      FitText(
                        speaker,
                        contrastBackground: bubbleColor,
                        style: textTheme.labelSmall?.copyWith(
                          // 发言者名也跟着气泡反色：原来写死 onSurfaceVariant，
                          // 深色气泡上就是"黑底黑字"。
                          color: FitText.inkFor(bubbleColor, colorScheme.surface)
                              .withValues(
                                alpha: FitText.isLightBackground(
                                        bubbleColor, colorScheme.surface)
                                    ? 0.85
                                    : 0.8,
                              ),
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (message.attachments.isNotEmpty) ...<Widget>[
                      _MessageAttachments(
                        attachments: message.attachments,
                        bubbleColor: bubbleColor,
                      ),
                      if (message.text.trim().isNotEmpty) const SizedBox(height: 6),
                    ],
                    Text.rich(
                      buildMessageTextSpan(
                        context,
                        message.text,
                        searchQuery,
                        colorScheme.tertiaryContainer.withValues(alpha: AppAlpha.a55),
                        bubbleColor: bubbleColor,
                      ),
                    ),
                    if (thoughtText.isNotEmpty && visibleThoughtMessageIds.contains(message.id)) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: AppRadius.xsAll,
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: AppAlpha.half)),
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
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: AppWeight.medium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            FitText(
                              thoughtText,
                              style: textTheme.bodySmall?.copyWith(height: AppLineHeight.body),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (message.text.isNotEmpty && showTokenCounts) ...<Widget>[
                      const SizedBox(height: 4),
                      FitText(
                        '字数 $charCount / Token $tokenCount',
                        contrastBackground: bubbleColor,
                        style: textTheme.bodySmall?.copyWith(
                          color: FitText.inkFor(
                            bubbleColor,
                            colorScheme.surface,
                          ).withValues(alpha: AppAlpha.muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );

            // 用户消息：右侧气泡，无操作按钮。
            if (isUser) {
              return Align(
                alignment: Alignment.centerRight,
                child: bubble,
              );
            }

            // 对方消息：操作按钮合并为一排放在气泡外（不遮挡文字），头像在气泡左侧。
            final bool actionable =
                message.kindEnum == MessageKind.message && message.text.trim().isNotEmpty;
            final ImageProvider? avatarProvider =
                (actionable && showMessageAvatar && avatarForMessage != null)
                    ? avatarForMessage!(message.speakerTaId)
                    : null;

            // 操作按钮排：朗读（仅端侧 TTS 开启时）、复制、重说、继续说（最近一条）。
            // 排布与三个开关的语义都恢复成原实现：showMessageCopy 管复制、
            // showMessageRetry 管重说、showMessageContinue 管继续说。
            final List<Widget> actionButtons = <Widget>[];
            if (actionable && ttsEnabled) {
              actionButtons.add(
                _MessagePlayButton(
                  text: message.text,
                  globalSeed: ttsGlobalSeed,
                  voiceSeedForTa: voiceSeedForTa,
                  speakerTaId: message.speakerTaId,
                  quoteOnly: ttsQuoteOnly,
                ),
              );
            }
            if (actionable && showMessageCopy) {
              actionButtons.add(
                _MessageActionButton(
                  tooltip: '复制',
                  icon: Icons.copy_rounded,
                  onTap: onCopyMessage == null
                      ? null
                      : () => onCopyMessage!(message.text),
                ),
              );
            }
            if (actionable && showMessageRetry && isLastAssistant) {
              actionButtons.add(
                _MessageActionButton(
                  tooltip: '重说',
                  icon: Icons.refresh_rounded,
                  onTap: onRetryMessage,
                ),
              );
            }
            if (actionable && showMessageContinue && isLastAssistant) {
              actionButtons.add(
                _MessageActionButton(
                  tooltip: '继续说',
                  icon: Icons.play_arrow_rounded,
                  onTap: onContinueMessage,
                ),
              );
            }

            return Align(
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 头像列：关闭头像开关时整体移除，气泡自动回挪。
                  if (avatarProvider != null) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MessageAvatarButton(avatar: avatarProvider),
                    ),
                  ],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (actionButtons.isNotEmpty) ...<Widget>[
                          // 操作按钮排（气泡外上方）：超宽时 Wrap 自动换行完整显示。
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.start,
                            children: actionButtons,
                          ),
                          const SizedBox(height: 4),
                        ],
                        bubble,
                        if (errorText != null)
                          _StreamErrorBanner(
                            message: errorText,
                            onRetry: onRetryFailed,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
  }
}
