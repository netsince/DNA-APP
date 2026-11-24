/// 会话视图（通用组件）。
///
/// 这一个类就是"一整个聊天界面"：背景立绘、标题栏、消息列表、输入岛、
/// 消息搜索、摘要、TTS、存档、导出都在这层里。它**不依赖路由**，
/// 只要给 `AppController` + 会话 id，就能渲染在任何地方。
///
/// 两种用法：
///
/// * `ChatSurfaceChrome.page`（默认）——自带 `Scaffold` 与顶栏，
///   等价于一个完整的聊天页（[ChatPage] 内部就是这么用的）。
/// * `ChatSurfaceChrome.embedded` —— **不建 `Scaffold`、不建顶栏**，
///   只渲染内容，交给宿主页面排版。适合嵌进别的页面（例如主页直接把
///   聊天铺满，或右侧栏里放一个会话）。
///
/// 用法：
/// ```dart
/// // 整页
/// Navigator.of(context).push(MaterialPageRoute<void>(
///   builder: (_) => ChatSurface(controller: c, conversationId: id),
/// ));
///
/// // 嵌在别的页面里（宿主的 Scaffold/AppBar 生效）
/// ChatSurface(
///   controller: c,
///   conversationId: id,
///   chrome: ChatSurfaceChrome.embedded,
/// )
/// ```
///
/// 注意：嵌入模式下宿主应保证自己有可用的 `Scaffold`（snackbar / 底部弹层
/// 会挂到最近的 `Scaffold` 上）。
library;

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/attachment_draft.dart';
import '../../models/message_attachment.dart';
import '../../services/attachment_image_loader.dart';
import '../../services/model_vision.dart';
import '../../utils/id_utils.dart';
import '../../utils/error_display.dart';
import '../../utils/fork_utils.dart';
import '../../utils/message_processor.dart';
import '../../utils/api_guard.dart';
import '../../utils/dialogs.dart';
import '../../utils/ui_feedback.dart';
import 'builders/chat_candidate_generator.dart';
import '../../widgets/app_content_frame.dart';
import '../../models/conversation.dart';
import '../../models/app_settings.dart';
import '../../models/quick_reply.dart';
import '../../models/ta.dart';
import '../../models/user_identity.dart';
import '../../models/service_results.dart';
import '../../models/world.dart';
import '../../services/conversation_export_import_service.dart';
import '../../services/bgm_player.dart';
import '../../services/image_storage.dart';
import '../../services/llm_request.dart';
import '../../services/llm_stream_chunk.dart';
import '../../services/ta_export_import_service.dart';
import '../../state/app_controller.dart';
import '../../widgets/conversation_export_import_dialogs.dart';
import '../../widgets/group_avatar.dart';
import 'chat_models.dart';
import 'chat_snapshot_store.dart';
import 'chat_stream_parser.dart';
import 'chat_token_counter.dart';
import 'chat_message_slice.dart';
import 'chat_message_builder.dart';
import 'chat_system_prompt.dart';
import 'world_lorebook.dart';
import 'state/chat_state.dart';
import 'state/chat_controller.dart';
import 'ui/widgets/chat_app_bar.dart';
import 'ui/widgets/animated_background.dart';
import 'ui/widgets/chat_input_bar.dart';
import 'ui/widgets/candidate_action_bar.dart';
import 'ui/widgets/chat_message_list.dart';
import 'ui/widgets/immersive_exit_button.dart';
import 'ui/widgets/speaker_bar.dart';
import 'ui/widgets/group_member_picker_sheet.dart';
import 'package:dna/widgets/fit_text.dart';
import '../../theme/tokens.dart';

import '../chat_page.dart';
import 'chat_surface_chrome.dart';
part 'state/chat_state_mixin.dart';
part 'ui/chat_ui_helpers.dart';
part 'ui/chat_search.dart';
part 'builders/chat_payload_builders.dart';
part 'chat_summary.dart';
part 'builders/chat_stream_handlers.dart';
part 'actions/chat_actions.dart';
part 'actions/chat_actions_send.dart';
part 'actions/chat_actions_inspiration.dart';
part 'actions/chat_actions_snapshots.dart';
part 'actions/chat_actions_summary_ui.dart';

class ChatSurface extends StatefulWidget {
  const ChatSurface({
    super.key,
    required this.controller,
    required this.conversationId,
    this.isGroup = false,
    this.chrome = ChatSurfaceChrome.page,
    this.contentLeftInset = 0,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
  });

  final AppController controller;
  final String conversationId;
  final bool isGroup;

  /// 外壳形态：[ChatSurfaceChrome.page] 自带 Scaffold/顶栏，
  /// [ChatSurfaceChrome.embedded] 只渲染内容（嵌进别的页面用）。
  final ChatSurfaceChrome chrome;

  /// 左侧留给「快速切换侧栏」的宽度:标题栏与聊天内容整体右移这么多,
  /// 但**背景立绘仍然铺满整宽** —— 于是侧栏浮层底下也是这张立绘,
  /// 磨砂透出来就与聊天区连成一片。
  final double contentLeftInset;

  /// 消息区横向拖动开始(为空表示不启用左右滑动)。
  ///
  /// 手势**只覆盖消息区**:标题栏与输入框不参与 —— 否则在输入框里
  /// 横向拖动选字会被误判成"切换角色"。
  final VoidCallback? onSwipeStart;

  /// 横向拖动中:转发本次的横向位移(跟手平移与预览由外层决定)。
  final ValueChanged<double>? onSwipeUpdate;

  /// 横向拖动结束(松手):由外层决定提交切换还是弹回原位。
  final VoidCallback? onSwipeEnd;

  @override
  State<ChatSurface> createState() => _ChatSurfaceState();
}
class _ChatSurfaceState extends State<ChatSurface>
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
  // 沉浸模式：隐藏顶栏与底部输入岛，纯享全屏立绘与对话。
  // 进入/退出：点屏幕上半区空白（原行为，见 docs/REGRESSION_AUDIT.md H1）、
  // ⋮ 菜单里的「沉浸模式」、以及沉浸态右上角的退出按钮。
  bool _immersiveUiHidden = false;

  // 半屏聊天时，消息区是否展开为全屏。
  // **由滚动自动切换**（原行为，见 docs/REGRESSION_AUDIT.md R2）：
  // 向上翻历史 → 展开；向下滚或滚到近底部 → 收敛回半屏；「回到底部」也收敛。
  bool _dynamicIsFullScreen = false;

  /// 沉浸态开关（顶栏按钮与沉浸态的退出按钮共用）。
  void _toggleImmersive() {
    setState(() => _immersiveUiHidden = !_immersiveUiHidden);
    if (_immersiveUiHidden) {
      // 进入沉浸就把输入焦点交还，避免键盘挡住整屏立绘。
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// 鼠标滚轮 / 触控板：向上滚展开全屏，向下滚收敛半屏（原行为 R2）。
  /// 「半屏+自动」两个开关都开时才响应滚动（原实现就是这条守卫）。
  bool get _dynamicHalfScreenOn =>
      widget.controller.settings.halfScreenChat &&
      widget.controller.settings.dynamicHalfScreen;

  void _onPointerSignalForHalfScreen(PointerSignalEvent event) {
    if (!_dynamicHalfScreenOn) return;
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy < -3) {
      if (!_dynamicIsFullScreen) setState(() => _dynamicIsFullScreen = true);
    } else if (event.scrollDelta.dy > 3) {
      if (_dynamicIsFullScreen) setState(() => _dynamicIsFullScreen = false);
    }
  }

  /// 滚动通知：向上翻历史展开、到近底部收敛（原行为 R2，阈值与原实现一致）。
  bool _onScrollForHalfScreen(ScrollNotification notification) {
    if (!_dynamicHalfScreenOn) return false;
    final ScrollMetrics metrics = notification.metrics;
    final bool isNearBottom = metrics.pixels >= metrics.maxScrollExtent - 24;
    if (isNearBottom) {
      if (_dynamicIsFullScreen) setState(() => _dynamicIsFullScreen = false);
    } else if (notification is ScrollUpdateNotification) {
      final double? delta = notification.scrollDelta;
      if (delta != null) {
        if (delta < -3) {
          if (!_dynamicIsFullScreen && metrics.pixels > 16) {
            setState(() => _dynamicIsFullScreen = true);
          }
        } else if (delta > 3) {
          if (_dynamicIsFullScreen) setState(() => _dynamicIsFullScreen = false);
        }
      }
    }
    return false;
  }

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
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[opening],
    );
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
    if (_dynamicIsFullScreen) {
      setState(() => _dynamicIsFullScreen = false);
    }
    _chatController.scrollToBottom();
  }

  /// 统计当前上下文（所有消息型气泡）占用的 token 总数。
  /// 仅当仪表盘开启时调用；[ChatTokenCounter] 自带缓存，文本不变时不重复编码。
  int _countContextTokens() {
    final String model = widget.controller.settings.selectedModel;
    int total = 0;
    for (final ConversationMessage m in _conversation.messages) {
      if (m.kindEnum != MessageKind.message) {
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
      if (message.kindEnum != MessageKind.message || message.role != 'assistant') {
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
    final String? path = useLandscape
        ? speaker?.images['landscape']
        : speaker?.images['portrait'];
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
    final List<TA> candidates = allTas
        .where((TA t) => !_memberTaIds.contains(t.id))
        .toList();
    if (candidates.isEmpty) {
      if (!mounted) {
        return;
      }
      showSnack(context, '没有可添加的TA了。');
      return;
    }
    final List<String>? updated = await showGroupMemberPickerSheet(
      context: context,
      candidates: candidates,
      accentTheme: _accentTheme,
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
    final bool hasAttachments = _conversation.messages
        .any((ConversationMessage m) => m.attachments.isNotEmpty);
    final ExportOptions? options = await showExportOptionsDialog(
      context: context,
      accentColor: _accent,
      hasAttachments: hasAttachments,
    );
    if (options == null || !mounted) {
      return;
    }
    final ExportImportResult<ConversationExportResult> result = await widget
        .controller
        .exportConversationsById(
          <String>[_conversation.id],
          includeCharacterCards: options.includeCharacterCards,
          format: options.format,
          includeAttachments: options.includeAttachments,
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

  ImageProvider? _avatarForTa(TA ta) {
    final String? path = ta.images['square'];
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


  // 横向拖动只做"转发":跟手平移、下一页预览、提交还是弹回,都由外层
  // (聊天页壳)决定 —— 只有它知道"下一个角色是谁、固定在哪个会话"。
  void _onSwipeStart(DragStartDetails details) => widget.onSwipeStart?.call();

  void _onSwipeUpdate(DragUpdateDetails details) =>
      widget.onSwipeUpdate?.call(details.delta.dx);

  void _onSwipeEnd(DragEndDetails details) => widget.onSwipeEnd?.call();
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
    final Color userBubble = schemeColor.withValues(
      alpha: AppAlpha.half * bubbleOpacity,
    );
    final Color assistantBubble = colorScheme.surfaceContainerHighest
        .withValues(alpha: bubbleOpacity);
    // 半屏聊天：聊天记录只显示在页面下半部分，上半部分留空查看背景。
    final bool halfScreenChat = widget.controller.settings.halfScreenChat;
    // 动态自适应：开启后，向上翻历史自动展开为全屏、滚回底部收成半屏。
    final bool dynamicHalfScreen =
        halfScreenChat && widget.controller.settings.dynamicHalfScreen;
    final bool isHalfScreenActive =
        halfScreenChat && (!dynamicHalfScreen || !_dynamicIsFullScreen);

    final bool useLandscape = screenSize.width >= screenSize.height;
    final String? bgPath = useLandscape
        ? ta?.images['landscape']
        : ta?.images['portrait'];
    final bool useImageBg =
        _conversation.backgroundMode == 'image' &&
        ((_isGroup) || (bgPath != null && bgPath.isNotEmpty));
    final String searchQuery = _searchController.text.trim();
    final List<int> searchMatches = _searching && searchQuery.isNotEmpty
        ? _computeSearchMatches(searchQuery)
        : <int>[];

    final bool isExtendBehind = useImageBg || halfScreenChat;

    // 背景层与前景分开:背景铺满整宽(侧栏浮层底下也要有角色立绘),
    // 而 Scaffold 整体按侧栏宽度内缩 —— 于是它的所有"家具"(底部提示条、
    // 悬浮按钮、底部弹层)都跟着让位,不会被侧栏压住。
    // 内容区（消息列表 + 输入岛）：整页与嵌入两种外壳共用这一份。
    final Widget content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: <Widget>[
            SafeArea(
              // 恒定的安全区：沉浸进出时不再让内容整体跳一格。
              top: isExtendBehind,
              bottom: false,
              child: Column(
                children: <Widget>[
                  // 发言控制条：沉浸时高度动画收起，不再瞬间消失。
                  AnimatedSize(
                    duration: AppMotion.medium,
                    curve: Curves.easeInOutCubicEmphasized,
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      opacity: _immersiveUiHidden ? 0.0 : 1.0,
                      duration: AppMotion.fast,
                      curve: Curves.easeOutCubic,
                      child: _immersiveUiHidden
                          ? const SizedBox(width: double.infinity)
                          : SpeakerBar(
                              showBar: _isGroup && _memberTas.isNotEmpty,
                              members: _memberTas,
                              activeTaId: _activeTaId,
                              avatarFor: _avatarForTa,
                              onSpeak: _triggerTaReply,
                              onAddMember: _showMemberPicker,
                              primaryContainer: colorScheme.primaryContainer,
                              surfaceContainerHighest:
                                  colorScheme.surfaceContainerHighest,
                              textTheme: textTheme,
                            ),
                    ),
                  ),
                  Expanded(
                    // 用自定义识别器而不是 GestureDetector:必须"横向明显
                    // 占优"才接管手势,否则上下滚动会被误判成左右切换。
                    // deferToChild:只有落在消息区(列表)上的拖动才算。
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      gestures: <Type, GestureRecognizerFactory>{
                        _HorizontalDominantDragRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _HorizontalDominantDragRecognizer
                            >(
                              () => _HorizontalDominantDragRecognizer(
                                debugOwner: this,
                              ),
                              (_HorizontalDominantDragRecognizer instance) {
                                instance
                                  ..onStart = widget.onSwipeStart == null
                                      ? null
                                      : _onSwipeStart
                                  ..onUpdate = widget.onSwipeUpdate == null
                                      ? null
                                      : _onSwipeUpdate
                                  ..onEnd = widget.onSwipeEnd == null
                                      ? null
                                      : _onSwipeEnd;
                              },
                            ),
                      },
                      child: Column(
                        children: <Widget>[
                          if (halfScreenChat)
                            AnimatedCrossFade(
                              // 上半区是留给立绘的空白，点它切换沉浸（原行为 H1）。
                              firstChild: SizedBox(
                                height:
                                    (screenSize.height - kToolbarHeight - 120) *
                                    0.45,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleImmersive,
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                              secondChild: const SizedBox.shrink(),
                              crossFadeState: isHalfScreenActive
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: const Duration(milliseconds: 320),
                              sizeCurve: Curves.easeInOutCubic,
                            ),
                          Expanded(
                            child: Listener(
                                onPointerSignal: _onPointerSignalForHalfScreen,
                                child:
                                    NotificationListener<ScrollNotification>(
                                      onNotification: _onScrollForHalfScreen,
                                      child: ShaderMask(
                                shaderCallback: (Rect bounds) => LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: const <Color>[
                                    Colors.transparent,
                                    Colors.black,
                                    Colors.black,
                                    Colors.transparent,
                                  ],
                                  stops: isHalfScreenActive
                                      ? const <double>[0.0, 0.05, 0.97, 1.0]
                                      : const <double>[0.0, 0.03, 0.97, 1.0],
                                ).createShader(bounds),
                                blendMode: BlendMode.dstIn,
                                child: AppContentFrame(
                                  child: ChatMessageList(
                                    conversation: _conversation,
                                    scrollController: _scrollController,
                                    messageKeys: _messageKeys,
                                    userBubble: userBubble,
                                    assistantBubble: assistantBubble,
                                    showTokenCounts: _showTokenCounts,
                                    searchQuery: searchQuery,
                                    thoughtsByMessageId: _thoughtsByMessageId,
                                    tokenCountForMessage:
                                        _tokenCountCallback.call,
                                    summaryById: _summaryById,
                                    onStartSummary: _startSummaryFromPrompt,
                                    onDismissSummary: _dismissSummaryPrompt,
                                    onShowMessageMenu: _showMessageMenu,
                                    summaryInProgress: _summaryInProgress,
                                    showSpeakerLabels: _isGroup,
                                    taNameForId: (String? id) => widget
                                        .controller
                                        .getTaById(id ?? '')
                                        ?.name,
                                    visibleThoughtMessageIds:
                                        _visibleThoughtMessageIds,
                                    ttsEnabled:
                                        widget.controller.settings.ttsEnabled,
                                    ttsGlobalSeed: widget
                                        .controller
                                        .settings
                                        .ttsGlobalSeed,
                                    voiceSeedForTa: (String? id) => widget
                                        .controller
                                        .getTaById(id ?? '')
                                        ?.voiceSeed,
                                    ttsQuoteOnly:
                                        widget.controller.settings.ttsQuoteOnly,
                                    showMessageAvatar: widget
                                        .controller
                                        .settings
                                        .showMessageAvatar,
                                    showMessageRetry: widget
                                        .controller
                                        .settings
                                        .showMessageRetry,
                                    showMessageCopy: widget
                                        .controller
                                        .settings
                                        .showMessageCopy,
                                    showMessageContinue: widget
                                        .controller
                                        .settings
                                        .showMessageContinue,
                                    avatarForMessage: _avatarForSpeakerTa,
                                    // 生成失败留在消息列表里可见（行内错误条 +
                                    // 行内「重试」），不再只靠 snackbar（审计 3.5）。
                                    // 重试复用现成的 _retryLastAssistant（重说那套）。
                                    streamErrors: _streamErrors,
                                    onRetryFailed: _retryLastAssistant,
                                    onRetryMessage: _retryLastAssistant,
                                    onCopyMessage: (String text) {
                                      Clipboard.setData(
                                        ClipboardData(text: text),
                                      );
                                      if (!mounted) return;
                                      showSnack(
                                        context,
                                        '已复制到剪贴板',
                                        behavior: SnackBarBehavior.floating,
                                      );
                                    },
                                    onContinueMessage: _continueFromContext,
                                  ),
                                ),
                              ),
                                      ),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_sending)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: assistantBubble,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const FitText('对方正在输入...'),
                        ),
                      ),
                    ),
                  if (_summaryInProgress)
                    AppContentFrame(
                      child: _SummaryProgressBar(
                        onCancel: _cancelSummary,
                        color: colorScheme.surfaceContainerHigh,
                        borderColor: colorScheme.outlineVariant,
                      ),
                    ),
                  AppContentFrame(
                    child: AnimatedCrossFade(
                      firstChild: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.controller.settings.showTokenDashboard)
                            _TokenDashboard(
                              usedTokens: _countContextTokens(),
                              budgetTokens:
                                  widget.controller.settings.maxContextTokens,
                              accent: schemeColor,
                            ),
                          Theme(
                            data: _accentTheme,
                            child: ChatInputBar(
                              controller: widget.controller,
                              inputController: _inputController,
                              inputFocusNode: _inputFocusNode,
                              sending: _sending,
                              attachments: _attachmentDraft,
                              visionEnabled: resolveVisionSupport(
                                widget.controller.activeModel,
                              ),
                              inspirationInProgress: _inspirationInProgress,
                              onSend: _send,
                              onStopGeneration: requestStopGeneration,
                              onStartInspiration: _startInspiration,
                              quickReplies:
                                  widget.controller.settings.quickReplies,
                              onQuickReply: _handleQuickReply,
                              halfScreen: isExtendBehind,
                            ),
                          ),
                        ],
                      ),
                      secondChild: const SizedBox.shrink(),
                      crossFadeState: _immersiveUiHidden
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: AppMotion.medium,
                      firstCurve: Curves.easeOutCubic,
                      secondCurve: Curves.easeInCubic,
                      sizeCurve: Curves.easeInOutCubicEmphasized,
                    ),
                  ),
                ],
              ),
            ),
            // 沉浸态的唯一常驻控件：见 ImmersiveExitButton。
            ImmersiveExitButton(
              visible: _immersiveUiHidden,
              onPressed: _toggleImmersive,
            ),
          ],
        ),
      );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: ColoredBox(color: colorScheme.surface)),
        if (useImageBg)
          Positioned.fill(
            child: _isGroup
                ? _buildGroupBackground(useLandscape)
                : (() {
                    final String bg = bgPath!;
                    final ImageProvider? image = _getCachedImage(bg);
                    if (image == null) return const SizedBox.shrink();
                    // GIF 动态背景：支持暂停第一帧 / 继续播放（状态随会话）。
                    // 静态立绘走普通 Image。
                    return AnimatedBackground(
                      image: image,
                      path: bg,
                      animate: _conversation.bgmAnimated,
                    );
                  })(),
          ),
        if (useImageBg)
          Positioned.fill(
            child: Builder(
              builder: (BuildContext context) {
                final double baseAlpha =
                    widget.controller.settings.chatMaskStrength / 100.0;
                final Color maskColor = colorScheme.surface.withValues(
                  alpha: baseAlpha,
                );
                final Color softMaskColor = colorScheme.surface.withValues(
                  alpha: baseAlpha * 0.20,
                );
                final Color halfMaskColor = colorScheme.surface.withValues(
                  alpha: baseAlpha * 0.60,
                );
                final Color clearColor = colorScheme.surface.withValues(
                  alpha: 0.0,
                );

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isHalfScreenActive
                          ? <Color>[
                              clearColor,
                              clearColor,
                              softMaskColor,
                              halfMaskColor,
                              maskColor,
                            ]
                          : <Color>[
                              maskColor,
                              maskColor,
                              maskColor,
                              maskColor,
                              maskColor,
                            ],
                      stops: const <double>[0.0, 0.32, 0.44, 0.60, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
        Positioned.fill(
          left: widget.contentLeftInset,
          // 嵌入模式：不建 Scaffold、不建顶栏，交给宿主；整页模式保持原样。
          child: widget.chrome == ChatSurfaceChrome.embedded
              ? content
              : Scaffold(
            backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: isExtendBehind || _immersiveUiHidden,
      appBar: PreferredSize(
        // 高度恒定：沉浸进出时不再让布局瞬间塌陷（原来 hidden 时把
        // preferredSize 换成 Size.zero，整页会往上跳一格）。隐藏交给
        // 滑动 + 淡出，内容靠 extendBodyBehindAppBar 顶到栏下面。
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: IgnorePointer(
          ignoring: _immersiveUiHidden,
          child: AnimatedSlide(
            offset: _immersiveUiHidden ? const Offset(0, -1) : Offset.zero,
            duration: AppMotion.medium,
            curve: Curves.easeInOutCubicEmphasized,
            child: AnimatedOpacity(
              opacity: _immersiveUiHidden ? 0.0 : 1.0,
              duration: AppMotion.fast,
              curve: Curves.easeOutCubic,
              child: ChatAppBar(
                  transparentBackground: isExtendBehind,
                  // 只按"当前是否真的半屏"给渐变：动态半屏滚成全屏后自动淡出。
                  showAppBarScrim: isHalfScreenActive,
                  searching: _searching,
                  searchController: _searchController,
                  searchMatchIndex: _searchMatchIndex,
                  searchMatchesCount: searchMatches.length,
                  onSearchChanged: _updateSearch,
                  onNavigateMatch: _navigateMatch,
                  onToggleSearch: _toggleSearch,
                  onScrollToBottom: _scrollToBottom,
                  onToggleBackground: _toggleBackground,
                  onToggleBgm: _toggleBgm,
                  bgmEnabled: _bgmEnabled,
                  showBgmOption:
                      !_isGroup && (_ta?.musicPath?.isNotEmpty ?? false),
                  onToggleBgmAnimation: _toggleBgmAnimation,
                  bgmAnimated: _conversation.bgmAnimated,
                  showBgmAnimationOption: _bgmIsGif,
                  rangeSummaryInProgress: _rangeSummaryInProgress,
                  summaryInProgress: _summaryInProgress,
                  showTokenCounts: _showTokenCounts,
                  onRangeSummary: _summarizeRecentRange,
                  onForceSummary: _forceSummaryPrompt,
                  onToggleTokens: () =>
                      setState(() => _showTokenCounts = !_showTokenCounts),
                  onManageSnapshots: _manageSnapshots,
                  onExport: _exportCurrentConversation,
                  backgroundMode: _conversation.backgroundMode,
                  ta: ta,
                  titleOverride: _isGroup
                      ? (_conversation.groupName.trim().isNotEmpty
                            ? _conversation.groupName.trim()
                            : '群聊')
                      : null,
                  // 沉浸入口收进 ⋮ 菜单（顶栏回到 3 个动作，见 R5）。
                  immersiveHidden: _immersiveUiHidden,
                  onToggleImmersive: _toggleImmersive,
                ),
            ),
          ),
        ),
      ),
      // 点空白只负责收键盘；沉浸态的退出走屏幕上那颗可见按钮
      // （不再用「点上半区空白」这种隐形热区，也不再用「点任意位置退出」
      // 当第二套入口）。
      body: content,
          ),
        ),
      ],
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
  _TokenCountCallback({required this.counter, required this.getModel});

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
              const SizedBox(width: 4),
              Expanded(
                child: FitText(
                  budgetTokens > 0
                      ? '上下文 $usedTokens / $budgetTokens Tokens'
                      : '上下文 $usedTokens Tokens（未设预算）',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 4),
              const FitText('正在生成摘要...'),
              const SizedBox(width: 8),
              TextButton(onPressed: onCancel, child: const FitText('停止')),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalDominantDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _HorizontalDominantDragRecognizer({super.debugOwner});

  /// 横向位移要达到纵向的多少倍才算横滑。
  static const double _dominance = 1.6;

  Offset _origin = Offset.zero;
  bool _decided = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _origin = event.position;
    _decided = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_decided && event is PointerMoveEvent) {
      final Offset delta = event.position - _origin;
      if (delta.dx.abs() >= delta.dy.abs() * _dominance) {
        _decided = true; // 判定为横滑:开始交给父类累积并竞争
      } else if (delta.dy.abs() > kTouchSlop) {
        _decided = true; // 纵向已明确:退出,让列表滚
        resolve(GestureDisposition.rejected);
        return;
      } else {
        return; // 方向未明:先不参与
      }
    }
    super.handleEvent(event);
  }
}
