import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../utils/fork_utils.dart';
import '../utils/message_processor.dart';
import '../utils/api_guard.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';
import '../models/conversation.dart';
import '../models/app_settings.dart';
import '../models/quick_reply.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../services/conversation_export_import_service.dart';
import '../services/image_storage.dart';
import '../services/ta_export_import_service.dart';
import '../state/app_controller.dart';
import '../widgets/conversation_export_import_dialogs.dart';
import '../widgets/group_avatar.dart';
import 'chat/chat_models.dart';
import 'chat/chat_snapshot_store.dart';
import 'chat/chat_stream_parser.dart';
import 'chat/chat_token_counter.dart';
import 'chat/chat_message_slice.dart';
import 'chat/chat_message_builder.dart';
import 'chat/chat_system_prompt.dart';
import 'chat/world_lorebook.dart';
import 'chat/state/chat_state.dart';
import 'chat/state/chat_controller.dart';
import 'chat/ui/widgets/chat_app_bar.dart';
import 'chat/ui/widgets/chat_input_bar.dart';
import 'chat/ui/widgets/chat_message_list.dart';
import 'package:dna/widgets/fit_text.dart';

part 'chat/state/chat_state_mixin.dart';
part 'chat/ui/chat_ui_helpers.dart';
part 'chat/ui/chat_search.dart';
part 'chat/builders/chat_payload_builders.dart';
part 'chat/chat_summary.dart';
part 'chat/builders/chat_stream_handlers.dart';
part 'chat/actions/chat_actions.dart';
part 'chat/actions/chat_actions_send.dart';
part 'chat/actions/chat_actions_inspiration.dart';
part 'chat/actions/chat_actions_snapshots.dart';
part 'chat/actions/chat_actions_summary_ui.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.conversationId,
    this.isGroup = false,
  });

  final AppController controller;
  final String conversationId;
  final bool isGroup;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with
        WidgetsBindingObserver,
        ChatStateMixin,
        ChatUiHelpers,
        ChatSearchHelpers,
        ChatPayloadBuilders,
        ChatSummaryHelpers,
        ChatStreamHandlers,
        ChatActions,
        ChatActionsSend,
        ChatActionsInspiration,
        ChatActionsSnapshots,
        ChatActionsSummaryUi {
  // 缓存回调函数避免重建
  late final _TokenCountCallback _tokenCountCallback = _TokenCountCallback(
    counter: _tokenCounter,
    getModel: () => widget.controller.settings.selectedModel,
  );

  @override
  Future<void> _ensureOpeningMessage() async {
    if (_isGroup) {
      return;
    }
    if (_conversation.messages.isNotEmpty) {
      return;
    }
    final TA? ta = _ta;
    if (ta == null || ta.opening.trim().isEmpty) {
      return;
    }
    final ConversationMessage opening = ConversationMessage(
      id: newId(),
      role: 'assistant',
      text: ta.opening.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(messages: <ConversationMessage>[opening]);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Future<void> _loadAccent() async {
    final s = widget.controller.settings;
    // 自定义模式：直接使用用户指定颜色，跳过角色卡取色。
    if (s.accentMode == 'custom' && s.customAccentColor != null) {
      if (mounted) {
        setState(() => _accent = Color(s.customAccentColor!));
      }
      return;
    }

    final TA? ta = _ta;
    // 自动模式下强调色跟随角色卡图片：优先用当前显示的背景图，否则依次回退到
    // 方形头像 / 竖屏图 / 横屏图，取第一张存在的图片，确保只要有角色卡图片就能取色。
    final bool useLandscape =
        MediaQuery.of(context).size.width >= MediaQuery.of(context).size.height;
    final List<String?> candidates = <String?>[
      if (_conversation.backgroundMode == 'image')
        ta?.images[useLandscape ? 'landscape' : 'portrait'],
      ta?.images['square'],
      ta?.images['portrait'],
      ta?.images['landscape'],
    ];
    String? ref;
    for (final String? candidate in candidates) {
      if (candidate != null &&
          candidate.isNotEmpty &&
          await ImageStorage.instance.readBytes(candidate) != null) {
        ref = candidate;
        break;
      }
    }
    if (ref == null) {
      if (mounted) {
        setState(() => _accent = null);
      }
      return;
    }

    try {
      // 提取图片主色调（用 dart:ui 按 64x64 解码，避免在后台 isolate 里
      // 走 ImageProvider 触发 PaintingBinding 未初始化的问题）
      final Color? dominantColor = await _extractDominantColor(ref);

      if (!mounted || dominantColor == null) {
        return;
      }
      setState(() {
        _accent = dominantColor;
      });
    } catch (e) {
      debugPrint('Failed to load accent color: $e');
    }
  }

  @override
  void _scrollToBottom() {
    _chatController.scrollToBottom();
  }

  /// 统计当前上下文（所有消息型气泡）占用的 token 总数。
  /// 仅当仪表盘开启时调用；[ChatTokenCounter] 自带缓存，文本不变时不重复编码。
  int _countContextTokens() {
    final String model = widget.controller.settings.selectedModel;
    int total = 0;
    for (final ConversationMessage m in _conversation.messages) {
      if (m.kind != 'message') {
        continue;
      }
      total += _tokenCounter.countTokens(
        model: model,
        messageId: m.id,
        text: m.text,
      );
    }
    return total;
  }

  TA? _lastAssistantSpeaker() {
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind != 'message' || message.role != 'assistant') {
        continue;
      }
      final String? taId = message.speakerTaId;
      if (taId != null && taId.isNotEmpty) {
        return widget.controller.getTaById(taId);
      }
      return _activeTa;
    }
    return null;
  }

  Widget _buildGroupBackground(bool useLandscape) {
    final TA? speaker = _lastAssistantSpeaker();
    final String? path = useLandscape ? speaker?.images['landscape'] : speaker?.images['portrait'];
    final ImageProvider? image = path != null ? _getCachedImage(path) : null;
    final bool hasImage = image != null;

    final Widget child = hasImage
        ? Image(
            image: image,
            key: ValueKey<String>('ta:$path'),
            fit: BoxFit.cover,
          )
        : LayoutBuilder(
            key: const ValueKey<String>('group-avatar'),
            builder: (BuildContext context, BoxConstraints constraints) {
              final double size = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              return Center(
                child: GroupAvatar(
                  tas: _memberTas,
                  size: size * 0.72,
                  radius: 18,
                ),
              );
            },
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }

  Future<void> _showMemberPicker() async {
    if (!_isGroup) {
      return;
    }
    final List<TA> allTas = widget.controller.activeTas;
    final List<TA> candidates = allTas.where((TA t) => !_memberTaIds.contains(t.id)).toList();
    if (candidates.isEmpty) {
      if (!mounted) {
        return;
      }
      showSnack(context, '没有可添加的TA了。');
      return;
    }
    final Set<String> selected = <String>{};
    final List<String>? updated = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: _accentTheme,
          child: StatefulBuilder(
            builder: (BuildContext context, void Function(void Function()) setDialogState) {
              return AlertDialog(
                title: const FitText('添加群成员'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final TA ta = candidates[index];
                    final bool checked = selected.contains(ta.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(ta.id);
                          } else {
                            selected.remove(ta.id);
                          }
                        });
                      },
                      title: FitText(ta.name.isEmpty ? '未命名TA' : ta.name),
                    );
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const FitText('取消'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty ? null : () => Navigator.of(context).pop(selected.toList()),
                  child: const FitText('添加'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
    if (updated == null || updated.isEmpty) {
      return;
    }
    final List<String> merged = <String>[
      ..._memberTaIds,
      ...updated.where((String id) => !_memberTaIds.contains(id)),
    ];
    _conversation = _conversation.copyWith(memberTaIds: merged);
    await widget.controller.upsertGroupConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _exportCurrentConversation() async {
    final ExportOptions? options = await showExportOptionsDialog(
      context: context,
      accentColor: _accent,
    );
    if (options == null || !mounted) {
      return;
    }
    final ExportImportResult<ConversationExportResult> result =
        await widget.controller.exportConversationsById(
      <String>[_conversation.id],
      includeCharacterCards: options.includeCharacterCards,
      format: options.format,
    );
    if (!mounted) {
      return;
    }
    if (!result.success || result.data == null) {
      showSnack(context, result.message ?? '导出失败');
      return;
    }
    await handleExportResult(context, result.data!);
  }

  ImageProvider? _avatarForTa(TA ta) {    final String? path = ta.images['square'];
    if (path == null || path.isEmpty) {
      return null;
    }
    return _getCachedImage(path);
  }

  /// 根据 speakerTaId 解析消息气泡头像（群聊/单聊通用，无头像返回 null）。
  ImageProvider? _avatarForSpeakerTa(String? taId) {
    final TA? ta = widget.controller.getTaById(taId ?? '');
    return ta == null ? null : _avatarForTa(ta);
  }

  Widget _buildSpeakerBar(Color primaryContainer, Color surfaceContainerHighest, TextTheme textTheme) {
    if (!_isGroup) {
      return const SizedBox.shrink();
    }
    final List<TA> tas = _memberTas;
    if (tas.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          const FitText('发言控制'),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tas.length,
                separatorBuilder: (_, int index) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final TA ta = tas[index];
                  final bool active = ta.id == _activeTaId;
                  final ImageProvider? avatar = _avatarForTa(ta);
                  return GestureDetector(
                    onTap: () => _triggerTaReply(ta),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: active
                              ? primaryContainer
                              : surfaceContainerHighest,
                          foregroundImage: avatar,
                          child: avatar == null
                              ? FitText(
                                  ta.name.isNotEmpty ? ta.name[0] : '?',
                                  style: textTheme.labelMedium,
                                )
                              : null,
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 56,
                          child: FitText(
                            ta.name.isEmpty ? '未命名' : ta.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(
            onPressed: _showMemberPicker,
            tooltip: '添加成员',
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 缓存 Theme 数据避免重复查找
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final Size screenSize = MediaQuery.sizeOf(context);

    final TA? ta = _ta;
    final Color schemeColor = _accent ?? colorScheme.primary;
    // 对话框透明度：0~100，乘入用户/助手气泡的 alpha，实现气泡透出背景。
    final double bubbleOpacity =
        widget.controller.settings.chatBubbleOpacity.clamp(0, 100) / 100;
    // 用户气泡保持偏淡层次（基准 0.5），并随滑块线性变化，0 时完全透明。
    final Color userBubble =
        schemeColor.withValues(alpha: 0.5 * bubbleOpacity);
    final Color assistantBubble = colorScheme.surfaceContainerHighest
        .withValues(alpha: bubbleOpacity);
    // 半屏聊天：聊天记录只显示在页面下半部分，上半部分留空查看背景。
    final bool halfScreenChat = widget.controller.settings.halfScreenChat;
    final bool useLandscape = screenSize.width >= screenSize.height;
    final String? bgPath = useLandscape ? ta?.images['landscape'] : ta?.images['portrait'];
    final bool useImageBg = _conversation.backgroundMode == 'image' &&
        ((_isGroup) || (bgPath != null && bgPath.isNotEmpty));
    final String searchQuery = _searchController.text.trim();
    final List<int> searchMatches =
        _searching && searchQuery.isNotEmpty ? _computeSearchMatches(searchQuery) : <int>[];

    return Scaffold(
      appBar: ChatAppBar(
        searching: _searching,
        searchController: _searchController,
        searchMatchIndex: _searchMatchIndex,
        searchMatchesCount: searchMatches.length,
        onSearchChanged: _updateSearch,
        onNavigateMatch: _navigateMatch,
        onToggleSearch: _toggleSearch,
        onScrollToBottom: _scrollToBottom,
        onToggleBackground: _toggleBackground,
        rangeSummaryInProgress: _rangeSummaryInProgress,
        summaryInProgress: _summaryInProgress,
        showTokenCounts: _showTokenCounts,
        onRangeSummary: _summarizeRecentRange,
        onForceSummary: _forceSummaryPrompt,
        onToggleTokens: () => setState(() => _showTokenCounts = !_showTokenCounts),
        onManageSnapshots: _manageSnapshots,
        onExport: _exportCurrentConversation,
        backgroundMode: _conversation.backgroundMode,
        ta: ta,
        titleOverride: _isGroup
            ? (_conversation.groupName.trim().isNotEmpty ? _conversation.groupName.trim() : '群聊')
            : null,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
        children: <Widget>[
          if (useImageBg)
            Positioned.fill(
              child: _isGroup
                  ? _buildGroupBackground(useLandscape)
                  : (() {
                      final ImageProvider? image = _getCachedImage(bgPath!);
                      if (image == null) return const SizedBox.shrink();
                      return Image(
                        image: image,
                        fit: BoxFit.cover,
                      );
                    })(),
            ),
          if (useImageBg)
            Positioned.fill(
              child: Container(
                color: colorScheme.surface.withValues(
                  alpha: widget.controller.settings.chatMaskStrength / 100,
                ),
              ),
            ),
          Column(
            children: <Widget>[
              _buildSpeakerBar(colorScheme.primaryContainer, colorScheme.surfaceContainerHighest, textTheme),
              Expanded(
                child: halfScreenChat
                    ? Column(
                        children: <Widget>[
                          // 上半部分留空，方便查看背景
                          const Expanded(child: SizedBox.expand()),
                          // 下半部分：聊天记录（上半部分留空，露出背景）。
                          // 顶部经 ShaderMask 渐隐：气泡接近上缘时逐渐淡出，
                          // 列表保持透明，过渡自然而非硬切。
                          Expanded(
                            child: ShaderMask(
                              shaderCallback: (Rect bounds) => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: const <Color>[
                                  Colors.transparent,
                                  Colors.black,
                                  Colors.black,
                                ],
                                stops: const <double>[0.0, 0.06, 1.0],
                              ).createShader(bounds),
                              blendMode: BlendMode.dstIn,
                              child: ChatMessageList(
                              conversation: _conversation,
                    scrollController: _scrollController,
                    messageKeys: _messageKeys,
                    userBubble: userBubble,
                    assistantBubble: assistantBubble,
                    showTokenCounts: _showTokenCounts,
                    searchQuery: searchQuery,
                    thoughtsByMessageId: _thoughtsByMessageId,
                    tokenCountForMessage: _tokenCountCallback.call,
                    summaryById: _summaryById,
                    onStartSummary: _startSummaryFromPrompt,
                    onDismissSummary: _dismissSummaryPrompt,
                    onShowMessageMenu: _showMessageMenu,
                    summaryInProgress: _summaryInProgress,
                    showSpeakerLabels: _isGroup,
                    taNameForId: (String? id) => widget.controller.getTaById(id ?? '')?.name,
                    visibleThoughtMessageIds: _visibleThoughtMessageIds,
                    ttsEnabled: widget.controller.settings.ttsEnabled,
                    ttsGlobalSeed: widget.controller.settings.ttsGlobalSeed,
                    voiceSeedForTa: (String? id) =>
                        widget.controller.getTaById(id ?? '')?.voiceSeed,
                    ttsQuoteOnly: widget.controller.settings.ttsQuoteOnly,
                    showMessageAvatar: widget.controller.settings.showMessageAvatar,
                    showMessageRetry: widget.controller.settings.showMessageRetry,
                    showMessageCopy: widget.controller.settings.showMessageCopy,
                    showMessageContinue: widget.controller.settings.showMessageContinue,
                    avatarForMessage: _avatarForSpeakerTa,
                    onRetryMessage: _retryLastAssistant,
                    onCopyMessage: (String text) {
                      Clipboard.setData(ClipboardData(text: text));
                      if (mounted) {
                        showSnack(
                          context,
                          '已复制到剪贴板',
                          behavior: SnackBarBehavior.floating,
                        );
                      }
                    },
                    onContinueMessage: _continueFromContext,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ChatMessageList(
                        conversation: _conversation,
                        scrollController: _scrollController,
                        messageKeys: _messageKeys,
                        userBubble: userBubble,
                        assistantBubble: assistantBubble,
                        showTokenCounts: _showTokenCounts,
                        searchQuery: searchQuery,
                        thoughtsByMessageId: _thoughtsByMessageId,
                        tokenCountForMessage: _tokenCountCallback.call,
                        summaryById: _summaryById,
                        onStartSummary: _startSummaryFromPrompt,
                        onDismissSummary: _dismissSummaryPrompt,
                        onShowMessageMenu: _showMessageMenu,
                        summaryInProgress: _summaryInProgress,
                        showSpeakerLabels: _isGroup,
                        taNameForId: (String? id) =>
                            widget.controller.getTaById(id ?? '')?.name,
                        visibleThoughtMessageIds: _visibleThoughtMessageIds,
                        ttsEnabled: widget.controller.settings.ttsEnabled,
                        ttsGlobalSeed: widget.controller.settings.ttsGlobalSeed,
                        voiceSeedForTa: (String? id) =>
                            widget.controller.getTaById(id ?? '')?.voiceSeed,
                        ttsQuoteOnly: widget.controller.settings.ttsQuoteOnly,
                        showMessageAvatar: widget.controller.settings.showMessageAvatar,
                        showMessageRetry: widget.controller.settings.showMessageRetry,
                        showMessageCopy: widget.controller.settings.showMessageCopy,
                        showMessageContinue: widget.controller.settings.showMessageContinue,
                        avatarForMessage: _avatarForSpeakerTa,
                        onRetryMessage: _retryLastAssistant,
                        onCopyMessage: (String text) {
                          Clipboard.setData(ClipboardData(text: text));
                          if (mounted) {
                            showSnack(
                              context,
                              '已复制到剪贴板',
                              behavior: SnackBarBehavior.floating,
                            );
                          }
                        },
                        onContinueMessage: _continueFromContext,
                      ),
              ),
              if (_sending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: assistantBubble,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const FitText('对方正在输入...'),
                    ),
                  ),
                ),
              if (_summaryInProgress)
                _SummaryProgressBar(
                  onCancel: _cancelSummary,
                  color: colorScheme.surfaceContainerHigh,
                  borderColor: colorScheme.outlineVariant,
                ),
              if (widget.controller.settings.showTokenDashboard)
                _TokenDashboard(
                  usedTokens: _countContextTokens(),
                  budgetTokens: widget.controller.settings.maxContextTokens,
                  accent: schemeColor,
                ),
              Theme(
                data: _accentTheme,
                child: ChatInputBar(
                  controller: widget.controller,
                  inputController: _inputController,
                  inputFocusNode: _inputFocusNode,
                  sending: _sending,
                  inspirationInProgress: _inspirationInProgress,
                  onSend: _send,
                  onStartInspiration: _startInspiration,
                  quickReplies: widget.controller.settings.quickReplies,
                  onQuickReply: _handleQuickReply,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }
}

// 提取图片主色调。使用 dart:ui 的 instantiateImageCodec 按 64x64 解码并交给
// PaletteGenerator.fromImage 计算，避免像 fromImageProvider 那样依赖
// PaintingBinding（在后台 isolate 里会报「Binding has not yet been initialized」）。
Future<Color?> _extractDominantColor(String ref) async {
  try {
    final Uint8List? bytes = await ImageStorage.instance.readBytes(ref);
    if (bytes == null) {
      return null;
    }
    // 解码时直接缩放到 64x64，既快又不阻塞 UI（单帧、小尺寸）。
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 64,
      targetHeight: 64,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final PaletteGenerator palette = await PaletteGenerator.fromImage(
      image,
      maximumColorCount: 4, // 减少颜色数量
    );
    final Color? color = palette.dominantColor?.color;
    image.dispose();
    codec.dispose();
    return color;
  } catch (e) {
    return null;
  }
}

// 缓存 token 计数回调
class _TokenCountCallback {
  _TokenCountCallback({
    required this.counter,
    required this.getModel,
  });

  final ChatTokenCounter counter;
  final String Function() getModel;

  int call(String messageId, String text) {
    return counter.countTokens(
      model: getModel(),
      messageId: messageId,
      text: text,
    );
  }
}

// 上下文 Token 实时仪表盘：显示当前上下文占用与预算。
class _TokenDashboard extends StatelessWidget {
  const _TokenDashboard({
    required this.usedTokens,
    required this.budgetTokens,
    required this.accent,
  });

  final int usedTokens;
  final int budgetTokens;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double? ratio = budgetTokens > 0 ? usedTokens / budgetTokens : null;
    final bool over = ratio != null && ratio > 1.0;
    final Color barColor = over ? cs.error : accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                over ? Icons.warning_amber_rounded : Icons.data_usage,
                size: 14,
                color: over ? cs.error : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FitText(
                  budgetTokens > 0
                      ? '上下文 $usedTokens / $budgetTokens Tokens'
                      : '上下文 $usedTokens Tokens（未设预算）',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 4,
                color: barColor,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 独立的摘要进度条组件
class _SummaryProgressBar extends StatelessWidget {
  const _SummaryProgressBar({
    required this.onCancel,
    required this.color,
    required this.borderColor,
  });

  final VoidCallback onCancel;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 6),
              const FitText('正在生成摘要...'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                child: const FitText('停止'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
