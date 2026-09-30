import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../utils/fork_utils.dart';
import '../utils/message_processor.dart';
import '../utils/api_guard.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_content_frame.dart';
import '../models/conversation.dart';
import '../models/app_settings.dart';
import '../models/quick_reply.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../services/conversation_export_import_service.dart';
import '../services/bgm_player.dart';
import '../services/image_storage.dart';
import '../services/llm_request.dart';
import '../services/llm_stream_chunk.dart';
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
import 'chat/ui/widgets/animated_background.dart';
import 'chat/ui/widgets/chat_input_bar.dart';
import 'chat/ui/widgets/chat_message_list.dart';
import 'package:dna/widgets/fit_text.dart';
import '../theme/tokens.dart';
import '../widgets/ta_avatar.dart';

part 'chat/state/chat_state_mixin.dart';
part 'chat/ui/chat_quick_sidebar.dart';
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

/// 聊天页。
///
/// 横屏、窗口够宽且设置里开启时,左侧带一条**快速切换侧栏**
/// (左列角色 1:1 头像 → 右列该角色的聊天);窄窗口/竖屏只有会话视图,
/// 与改造前完全一致。
///
/// ## 「原地换会话」是怎么做到的
///
/// 侧栏切换只改 [_conversationId],会话视图带 `ValueKey(会话 id)`:
/// id 一变,旧 State 走正常 dispose、新 State 正常 init —— **不新增
/// 路由、没有页面转场动画**,视觉上就是消息区顺滑换掉。
///
/// 这样切换时需要重置的东西(消息键、强调色重新取色、滚动位置、
/// 搜索状态、在途摘要、TTS 播放)全部沿用既有的 init/dispose 逻辑,
/// 不必另写一套"重新初始化",也就不会漏字段。代价是旧 State 被销毁:
/// 输入框草稿会丢、在途生成会被取消(与"退出聊天页再进来"一致)。
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

class _ChatPageState extends State<ChatPage> {
  /// 当前展示的会话:侧栏切换只改它。
  late String _conversationId = widget.conversationId;

  /// 每个角色「固定」在哪个会话上:左右滑动切角色时用它,而不是每次
  /// 都跳"最近活跃" —— 否则你正在看某个旧会话,滑走再滑回来会被
  /// 传送到别的会话去。当前会话一变就更新它。
  final Map<String, String> _fixedConversationByTa = <String, String>{};

  @override
  void initState() {
    super.initState();
    _rememberCurrentConversation();
  }

  /// 侧栏收起状态:初值取自设置(**记住上次的折叠/展开**),
  /// 切换会话时不丢,点把手时写回设置。
  late bool _sidebarCollapsed =
      widget.controller.settings.chatQuickSidebarCollapsed;

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    widget.controller.saveChatQuickSidebarCollapsed(_sidebarCollapsed);
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _conversationId = widget.conversationId;
      _rememberCurrentConversation();
    }
  }

  void _openConversation(String id) {
    if (id == _conversationId) {
      return;
    }
    setState(() {
      _conversationId = id;
      _rememberCurrentConversation();
    });
  }

  /// 以当前会话为准判断是不是群聊:侧栏只能切到 1:1,若沿用打开时的
  /// isGroup 会带着"群聊"标记渲染 1:1 会话。
  bool get _isGroupConversation =>
      _conversationById(_conversationId)?.isGroup ?? widget.isGroup;

  void _rememberCurrentConversation() {
    final Conversation? current = _conversationById(_conversationId);
    if (current != null && !current.isGroup) {
      _fixedConversationByTa[current.taId] = current.id;
    }
  }

  Conversation? _conversationById(String id) {
    for (final Conversation conversation in widget.controller.conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  /// 参与左右滑动的角色:与桌面侧栏左列同构 —— 按「我家」顺序,
  /// 只保留有非归档 1:1 会话的角色(群聊不参与)。
  List<TA> _swipeCharacters() {
    final Set<String> withChats = <String>{
      for (final Conversation conversation in widget.controller.conversations)
        if (!conversation.isGroup && !conversation.archived) conversation.taId,
    };
    return <TA>[
      for (final TA ta in widget.controller.tas)
        if (withChats.contains(ta.id)) ta,
    ];
  }

  /// 该角色最近活跃的非归档 1:1 会话(只作兜底:没有"固定会话"时用)。
  ///
  /// 消息时间用的是真实发送时刻(毫秒);老数据可能缺这个字段而被
  /// 反序列化成 0,所以这里用"最大值"比较,全为 0 时退化成列表顺序。
  Conversation? _mostRecentConversationOf(String taId) {
    Conversation? best;
    int bestAt = -1;
    for (final Conversation conversation in widget.controller.conversations) {
      if (conversation.isGroup ||
          conversation.archived ||
          conversation.taId != taId) {
        continue;
      }
      final int at = conversation.messages.isEmpty
          ? 0
          : conversation.messages.last.timestamp;
      if (at > bestAt) {
        bestAt = at;
        best = conversation;
      }
    }
    return best;
  }

  /// 该角色"固定"在哪个会话:优先用记住的那个(会话还在且没被归档),
  /// 否则回退到最近活跃的那个。
  String? _conversationForCharacter(String taId) {
    final String? fixed = _fixedConversationByTa[taId];
    if (fixed != null) {
      final Conversation? conversation = _conversationById(fixed);
      if (conversation != null && !conversation.archived) {
        return fixed;
      }
    }
    return _mostRecentConversationOf(taId)?.id;
  }

  /// 左右滑动切换角色:[direction] = 1 下一个,-1 上一个;到头绕回。
  ///
  /// 群聊不参与(在群聊里滑动不生效);只有一个角色时也没什么可切。
  void _swipeCharacter(int direction) {
    if (!widget.controller.settings.chatSwipeSwitch) {
      return;
    }
    final Conversation? current = _conversationById(_conversationId);
    if (current == null || current.isGroup) {
      return;
    }
    final List<TA> characters = _swipeCharacters();
    if (characters.length < 2) {
      return;
    }
    final int index = characters.indexWhere((TA ta) => ta.id == current.taId);
    if (index < 0) {
      return;
    }
    final int count = characters.length;
    final int target = ((index + direction) % count + count) % count;
    final String? targetId = _conversationForCharacter(characters[target].id);
    if (targetId != null) {
      _openConversation(targetId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool wideEnough =
        MediaQuery.sizeOf(context).width >= AppSize.chatSidebarMinWidth;
    final bool showSidebar =
        landscape && wideEnough && widget.controller.settings.chatQuickSidebar;
    final bool swipeEnabled = widget.controller.settings.chatSwipeSwitch;

    // 收起/展开是**一条动画**驱动的:它同时决定侧栏浮层的宽度与聊天
    // 内容的内缩量,所以两列是滑出去/滑进来的,内容也跟着让位,
    // 不会一边跳一边不动。初值直接取目标值 ⇒ 进入页面时按上次的
    // 折叠状态就位,不会先展开再收起。
    final double targetInset = !showSidebar
        ? 0
        : (_sidebarCollapsed
              ? AppSize.chatSidebarHandle
              : kChatSidebarFullWidth);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetInset),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double inset, Widget? _) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              // 换会话:整页淡入淡出。侧栏是**浮层**、不在这个切换器里,
              // 所以切换时它稳稳留在原地,不会跟着闪。
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: ChatConversationView(
                  key: ValueKey<String>(_conversationId),
                  controller: widget.controller,
                  conversationId: _conversationId,
                  isGroup: _isGroupConversation,
                  contentLeftInset: inset,
                  onSwipeNext: swipeEnabled
                      ? () => _swipeCharacter(1)
                      : null,
                  onSwipePrevious: swipeEnabled
                      ? () => _swipeCharacter(-1)
                      : null,
                ),
              ),
            ),
            if (showSidebar)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ChatQuickSidebar(
                  controller: widget.controller,
                  currentConversationId: _conversationId,
                  onSelectConversation: _openConversation,
                  width: inset,
                  collapsed: _sidebarCollapsed,
                  onToggleCollapsed: _toggleSidebar,
                ),
              ),
          ],
        );
      },
    );
  }
}
class ChatConversationView extends StatefulWidget {
  const ChatConversationView({
    super.key,
    required this.controller,
    required this.conversationId,
    this.isGroup = false,
    this.contentLeftInset = 0,
    this.onSwipeNext,
    this.onSwipePrevious,
  });

  final AppController controller;
  final String conversationId;
  final bool isGroup;

  /// 左侧留给「快速切换侧栏」的宽度:标题栏与聊天内容整体右移这么多,
  /// 但**背景立绘仍然铺满整宽** —— 于是侧栏浮层底下也是这张立绘,
  /// 磨砂透出来就与聊天区连成一片。
  final double contentLeftInset;

  /// 消息区左滑(下一个角色)。为空表示不启用左右滑动。
  ///
  /// 手势**只覆盖消息区**:标题栏与输入框不参与 —— 否则在输入框里
  /// 横向拖动选字会被误判成"切换角色"。
  final VoidCallback? onSwipeNext;

  /// 消息区右滑(上一个角色)。
  final VoidCallback? onSwipePrevious;

  @override
  State<ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<ChatConversationView>
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
  // 沉浸模式：隐藏顶栏与底部输入岛，纯享全屏立绘与对话
  bool _immersiveUiHidden = false;

  // 动态自适应滚动：向上翻看历史记录时临时展开为全屏
  bool _dynamicIsFullScreen = false;

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
    final Set<String> selected = <String>{};
    final List<String>? updated = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: _accentTheme,
          child: StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setDialogState,
                ) {
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
                        onPressed: selected.isEmpty
                            ? null
                            : () =>
                                  Navigator.of(context).pop(selected.toList()),
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
    final ExportImportResult<ConversationExportResult> result = await widget
        .controller
        .exportConversationsById(
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

  Widget _buildSpeakerBar(
    Color primaryContainer,
    Color surfaceContainerHighest,
    TextTheme textTheme,
  ) {
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
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          const FitText('发言控制'),
          const SizedBox(width: 8),
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

  /// 本次横向拖动的累计位移(正 = 向右)。
  double _swipeDx = 0;

  void _onSwipeStart(DragStartDetails details) => _swipeDx = 0;

  void _onSwipeUpdate(DragUpdateDetails details) => _swipeDx += details.delta.dx;

  void _onSwipeEnd(DragEndDetails details) {
    // 用累计位移判定而不是速度:慢速长拖也应该生效,行为更可预期。
    const double threshold = 64;
    final double dx = _swipeDx;
    _swipeDx = 0;
    if (dx <= -threshold) {
      widget.onSwipeNext?.call();
    } else if (dx >= threshold) {
      widget.onSwipePrevious?.call();
    }
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
    final Color userBubble = schemeColor.withValues(alpha: 0.5 * bubbleOpacity);
    final Color assistantBubble = colorScheme.surfaceContainerHighest
        .withValues(alpha: bubbleOpacity);
    // 半屏聊天：聊天记录只显示在页面下半部分，上半部分留空查看背景。
    final bool halfScreenChat = widget.controller.settings.halfScreenChat;
    final bool dynamicHalfScreen =
        halfScreenChat && widget.controller.settings.dynamicHalfScreen;
    // 当开启自适应滚动且正在向上查看历史记录时，动态变为全屏模式
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
          child: Scaffold(
            backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: isExtendBehind,
      appBar: PreferredSize(
        preferredSize: _immersiveUiHidden
            ? Size.zero
            : const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          opacity: _immersiveUiHidden ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: _immersiveUiHidden
              ? const SizedBox.shrink()
              : ChatAppBar(
                  transparentBackground: isExtendBehind,
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
                ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_immersiveUiHidden) {
            setState(() => _immersiveUiHidden = false);
          } else {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        },
        child: Stack(
          children: <Widget>[
            SafeArea(
              top: isExtendBehind && !_immersiveUiHidden,
              bottom: false,
              child: Column(
                children: <Widget>[
                  if (!_immersiveUiHidden)
                    _buildSpeakerBar(
                      colorScheme.primaryContainer,
                      colorScheme.surfaceContainerHighest,
                      textTheme,
                    ),
                  Expanded(
                    child: GestureDetector(
                      // deferToChild:只有落在消息区(列表)上的拖动才算,
                      // 手势不越界到输入框/标题栏。
                      behavior: HitTestBehavior.deferToChild,
                      onHorizontalDragStart:
                          widget.onSwipeNext == null &&
                              widget.onSwipePrevious == null
                          ? null
                          : _onSwipeStart,
                      onHorizontalDragUpdate:
                          widget.onSwipeNext == null &&
                              widget.onSwipePrevious == null
                          ? null
                          : _onSwipeUpdate,
                      onHorizontalDragEnd:
                          widget.onSwipeNext == null &&
                              widget.onSwipePrevious == null
                          ? null
                          : _onSwipeEnd,
                      child: Listener(
                        onPointerSignal: (PointerSignalEvent event) {
                        if (!dynamicHalfScreen) {
                          return;
                        }
                        if (event is PointerScrollEvent) {
                          // 鼠标滚轮向上滚动（dy < -3，向上翻看历史记录）：展开为全屏
                          if (event.scrollDelta.dy < -3) {
                            if (!_dynamicIsFullScreen) {
                              setState(() => _dynamicIsFullScreen = true);
                            }
                          } else if (event.scrollDelta.dy > 3) {
                            // 鼠标滚轮向下滚动（dy > 3，向最新消息方向回滚）：中途即刻收敛为半屏
                            if (_dynamicIsFullScreen) {
                              setState(() => _dynamicIsFullScreen = false);
                            }
                          }
                        }
                      },
                      child: Column(
                        children: <Widget>[
                          if (halfScreenChat)
                            AnimatedCrossFade(
                              firstChild: SizedBox(
                                height:
                                    (screenSize.height - kToolbarHeight - 120) *
                                    0.45,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setState(() {
                                      _immersiveUiHidden = !_immersiveUiHidden;
                                      if (_immersiveUiHidden) {
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                      }
                                    });
                                  },
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
                            child: NotificationListener<ScrollNotification>(
                              onNotification:
                                  (ScrollNotification notification) {
                                    if (!dynamicHalfScreen) {
                                      return false;
                                    }
                                    final ScrollMetrics metrics =
                                        notification.metrics;
                                    final bool isNearBottom =
                                        metrics.pixels >=
                                        metrics.maxScrollExtent - 24;

                                    if (isNearBottom) {
                                      // 滚动到达底部：自动收敛为半屏
                                      if (_dynamicIsFullScreen) {
                                        setState(
                                          () => _dynamicIsFullScreen = false,
                                        );
                                      }
                                    } else if (notification
                                        is ScrollUpdateNotification) {
                                      final double? delta =
                                          notification.scrollDelta;
                                      if (delta != null) {
                                        if (delta < -3) {
                                          // 向上滚动（翻看上方历史记录，含鼠标滚轮与手势）：自动展开为全屏
                                          if (!_dynamicIsFullScreen &&
                                              metrics.pixels > 16) {
                                            setState(
                                              () => _dynamicIsFullScreen = true,
                                            );
                                          }
                                        } else if (delta > 3) {
                                          // 向下滚动（向最新消息方向回滚）：中途即刻收敛为半屏
                                          if (_dynamicIsFullScreen) {
                                            setState(
                                              () =>
                                                  _dynamicIsFullScreen = false,
                                            );
                                          }
                                        }
                                      }
                                    } else if (notification
                                        is UserScrollNotification) {
                                      if (notification.direction ==
                                          ScrollDirection.forward) {
                                        // 触摸手势从上往下滑动（向上翻看历史记录）：自动展开为全屏
                                        if (!_dynamicIsFullScreen &&
                                            metrics.pixels > 16) {
                                          setState(
                                            () => _dynamicIsFullScreen = true,
                                          );
                                        }
                                      } else if (notification.direction ==
                                          ScrollDirection.reverse) {
                                        // 触摸手势从下往上滑动（向最新消息方向回滚）：中途即刻收敛为半屏
                                        if (_dynamicIsFullScreen) {
                                          setState(
                                            () => _dynamicIsFullScreen = false,
                                          );
                                        }
                                      }
                                    }
                                    return false;
                                  },
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
                                    onRetryMessage: _retryLastAssistant,
                                    onCopyMessage: (String text) {
                                      Clipboard.setData(
                                        ClipboardData(text: text),
                                      );
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
                            ),
                          ),
                        ],
                      ),
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
                      duration: const Duration(milliseconds: 200),
                    ),
                  ),
                ],
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
