import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/conversation_labels.dart';
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
import '../services/resume_service.dart';
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

/// 左右滑动退场方式。
enum _OutgoingMode {
  /// 跟手翻页:旧页按手指方向滑出去。
  slide,

  /// 侧栏/列表切换:旧页淡出。
  fade,
}

/// 左右滑动的目标:角色 + 该角色"固定"的那个会话。
class _SwipeTarget {
  const _SwipeTarget({required this.ta, required this.conversationId});

  final TA ta;
  final String conversationId;
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  /// 当前展示的会话。
  late String _conversationId = widget.conversationId;

  /// 每个角色「固定」在哪个会话上:左右滑动切角色时用它,而不是每次
  /// 都跳"最近活跃" —— 否则你正在看某个旧会话,滑走再滑回来会被
  /// 传送到别的会话去。当前会话一变就更新它。
  final Map<String, String> _fixedConversationByTa = <String, String>{};

  /// 会话视图的 GlobalKey:退场时旧视图要**换位置**(从当前槽位挪到
  /// 退场层)但仍然保留 State —— 否则滑出去的途中会闪成空白。
  final Map<String, GlobalKey> _viewKeys = <String, GlobalKey>{};

  /// 侧栏收起状态:初值取自设置(**记住上次的折叠/展开**),
  /// 切换会话时不丢,点把手时写回设置。
  late bool _sidebarCollapsed =
      widget.controller.settings.chatQuickSidebarCollapsed;

  /// 最近一次布局算出的侧栏宽度(构建退场视图时需要)。
  double _lastInset = 0;

  // ---- 左右滑动(跟手翻页)----

  /// 手指拖动中的实时位移(负 = 向左滑 = 下一个角色)。
  double _dragDx = 0;

  /// 拖动中露出的"下一页"预览(为空表示不显示)。
  _SwipeTarget? _peekTarget;

  /// 提交切换时:旧会话视图留在上层做退场动画。
  Widget? _outgoingView;
  _OutgoingMode _outgoingMode = _OutgoingMode.slide;

  /// 退场/回弹动画。
  late final AnimationController _settleAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  double _animFrom = 0;
  double _animTo = 0;

  /// 拖动位移单独走 ValueNotifier：跟手阶段只更新「平移」这一层。
  ///
  /// 以前每次拖动都 setState，整页（消息列表、侧栏磨砂、标题栏）每帧重建一遍；
  /// 拖动一次就有几十个 move 事件，等于几十次全页 build —— 这是切换卡顿的主因。
  final ValueNotifier<double> _dragNotifier = ValueNotifier<double>(0);

  /// 拖动预览视图缓存：目标与方向不变时复用同一个 Widget 实例。
  Widget? _peekView;
  String? _peekViewId;
  bool? _peekViewFromRight;

  /// 会话视图缓存（与动画无关，见 [_viewFor]）。
  Widget? _cachedView;
  String? _cachedViewConversationId;
  double _cachedViewInset = double.nan;
  bool _cachedViewSwipe = true;

  @override
  void initState() {
    super.initState();
    _rememberCurrentConversation();
  }

  @override
  void dispose() {
    _dragNotifier.dispose();
    _settleAnim.dispose();
    super.dispose();
  }

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

  GlobalKey _viewKey(String conversationId) => _viewKeys.putIfAbsent(
    conversationId,
    () => GlobalKey(debugLabel: 'chat-view-$conversationId'),
  );

  /// 侧栏/列表点进来的切换:旧页淡出。
  void _openConversation(String id) {
    _switchConversation(id, mode: _OutgoingMode.fade);
  }

  /// 切换会话:新会话立刻在下面就位,旧会话留在上层做退场动画。
  void _switchConversation(
    String id, {
    required _OutgoingMode mode,
    double from = 0,
    double? to,
  }) {
    if (id == _conversationId) {
      return;
    }
    final Widget outgoing = _buildView(_conversationId, _lastInset);
    final double width = MediaQuery.sizeOf(context).width;
    setState(() {
      _outgoingView = outgoing;
      _outgoingMode = mode;
      _conversationId = id;
      _rememberCurrentConversation();
      _peekTarget = null;
      _peekView = null;
      _peekViewId = null;
      _peekViewFromRight = null;
    });
    _settle(
      from: mode == _OutgoingMode.fade ? 0 : from,
      to: to ?? (mode == _OutgoingMode.fade ? 1 : -width),
      onDone: () => setState(() {
        _outgoingView = null;
        _dragDx = 0;
        _dragNotifier.value = 0;
      }),
    );
  }

  void _settle({
    required double from,
    required double to,
    required VoidCallback onDone,
  }) {
    _animFrom = from;
    _animTo = to;
    _settleAnim.forward(from: 0).whenComplete(() {
      if (mounted) {
        onDone();
      }
    });
  }

  /// 当前动画进度(0~1,已缓动)。
  double get _settleT => Curves.easeOutCubic.transform(_settleAnim.value);

  bool get _swipeEnabled => widget.controller.settings.chatSwipeSwitch;

  // ---- 滑动回调(由聊天视图的消息区转发过来)----

  void _onSwipeStart() {
    if (!_swipeEnabled) {
      return;
    }
    _settleAnim.stop();
    _dragDx = 0;
    _dragNotifier.value = 0;
    setState(() {
      _peekTarget = null;
      _peekView = null;
      _peekViewId = null;
      _peekViewFromRight = null;
    });
  }

  void _onSwipeUpdate(double dx) {
    if (!_swipeEnabled) {
      return;
    }
    _dragDx += dx;
    _dragNotifier.value = _dragDx;
    // 拖动中就露出"下一页"是谁,松手前心里有数。
    // 方向与目标没变时不触发整页 setState —— 只是平移在动。
    final _SwipeTarget? next = _swipeTarget(dx < 0 ? 1 : -1);
    if (next?.conversationId != _peekTarget?.conversationId) {
      setState(() {
        _peekTarget = next;
        _peekView = null;
        _peekViewId = null;
        _peekViewFromRight = null;
      });
    }
  }

  void _onSwipeEnd() {
    if (!_swipeEnabled) {
      return;
    }
    const double threshold = 64;
    final double dx = _dragDx;
    final int direction = dx <= -threshold ? 1 : (dx >= threshold ? -1 : 0);
    final _SwipeTarget? target = direction == 0
        ? null
        : _swipeTarget(direction);
    if (target == null) {
      // 不够阈值(或没有可切的角色):弹回原位。
      _settle(
        from: dx,
        to: 0,
        onDone: () => setState(() {
          _dragDx = 0;
          _dragNotifier.value = 0;
          _peekTarget = null;
        }),
      );
      return;
    }
    final double width = MediaQuery.sizeOf(context).width;
    _switchConversation(
      target.conversationId,
      mode: _OutgoingMode.slide,
      from: dx,
      to: direction > 0 ? -width : width,
    );
  }

  // ---- 数据 ----

  /// 以会话为准判断是不是群聊:侧栏只能切到 1:1,若沿用打开时的
  /// isGroup 会带着"群聊"标记渲染 1:1 会话。
  bool _isGroupOf(String conversationId) =>
      _conversationById(conversationId)?.isGroup ??
      (conversationId == widget.conversationId && widget.isGroup);

  void _rememberCurrentConversation() {
    // 「上次聊天」指针的**唯一写入点**：打开聊天页、页内切换会话都经过这里
    // （见 ResumeService 的类注释）。群聊也记 —— 续玩要能回到群聊，不只是 1:1。
    unawaited(ResumeService.instance.rememberOpened(_conversationId));

    final Conversation? current = _conversationById(_conversationId);
    if (current != null && !current.isGroup) {
      _fixedConversationByTa[current.taId] = current.id;
    }
  }

  /// 按 id 查会话（单聊 + 群聊）。侧栏、滑动、群聊判定都走这里，
  /// 少查一半列表就会把群聊当成单聊渲染。
  Conversation? _conversationById(String id) =>
      widget.controller.getConversationById(id);

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
  /// 反序列化成 0,所以这里取"最大值",全为 0 时退化成列表顺序。
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

  /// 相对当前角色偏移 [direction] 的目标(1 下一个 / -1 上一个,到头绕回)。
  ///
  /// 群聊不参与(在群聊里滑动拿不到目标 ⇒ 无动作);只有一个角色时
  /// 也没什么可切。
  _SwipeTarget? _swipeTarget(int direction) {
    final Conversation? current = _conversationById(_conversationId);
    if (current == null || current.isGroup) {
      return null;
    }
    final List<TA> characters = _swipeCharacters();
    if (characters.length < 2) {
      return null;
    }
    final int index = characters.indexWhere((TA ta) => ta.id == current.taId);
    if (index < 0) {
      return null;
    }
    final int count = characters.length;
    final int at = ((index + direction) % count + count) % count;
    final String? id = _conversationForCharacter(characters[at].id);
    if (id == null) {
      return null;
    }
    return _SwipeTarget(ta: characters[at], conversationId: id);
  }

  // ---- 渲染 ----

  Widget _buildView(String conversationId, double inset) {
    return ChatConversationView(
      key: _viewKey(conversationId),
      controller: widget.controller,
      conversationId: conversationId,
      isGroup: _isGroupOf(conversationId),
      contentLeftInset: inset,
      onSwipeStart: _swipeEnabled ? _onSwipeStart : null,
      onSwipeUpdate: _swipeEnabled ? _onSwipeUpdate : null,
      onSwipeEnd: _swipeEnabled ? _onSwipeEnd : null,
    );
  }

  /// 取当前会话视图：**同一个 Widget 实例**重复使用。
  ///
  /// 切换/滑动的动画帧只该重建外面的 Transform/Opacity 外壳；如果每帧都
  /// 重新构造 ChatConversationView，整棵消息列表都会被 build 一遍。
  /// Flutter 在 updateChild 里对「同一个 Widget 实例」有快速路径，
  /// 只要实例不变，这棵子树直接跳过 build。
  Widget _viewFor(String conversationId, double inset) {
    final bool swipe = _swipeEnabled;
    final Widget? cached = _cachedView;
    if (cached != null &&
        _cachedViewConversationId == conversationId &&
        _cachedViewSwipe == swipe &&
        (_cachedViewInset - inset).abs() < 0.01) {
      return cached;
    }
    final Widget view = _buildView(conversationId, inset);
    _cachedView = view;
    _cachedViewConversationId = conversationId;
    _cachedViewInset = inset;
    _cachedViewSwipe = swipe;
    return view;
  }

  /// 拖动预览视图：目标与方向不变时复用同一个实例。
  Widget? _peekFor(BuildContext context, {required double offset}) {
    final _SwipeTarget? target = _peekTarget;
    if (target == null) {
      return null;
    }
    final bool fromRight = offset < 0;
    if (_peekView != null &&
        _peekViewId == target.conversationId &&
        _peekViewFromRight == fromRight) {
      return _peekView;
    }
    final Widget view = _buildSwipePeek(context, target, fromRight);
    _peekView = view;
    _peekViewId = target.conversationId;
    _peekViewFromRight = fromRight;
    return view;
  }

  /// 拖动时露出的"下一页"预览:一张中性底 + 目标角色的头像与名字,
  /// 让人在松手前就知道要切到谁。
  Widget _buildSwipePeek(
    BuildContext context,
    _SwipeTarget target,
    bool fromRight,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Align(
        alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TaAvatar(ta: target.ta, size: 64, borderRadius: 16),
              const SizedBox(height: 12),
              FitText(
                target.ta.name.trim().isEmpty ? '未命名TA' : target.ta.name,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Icon(
                fromRight ? Icons.chevron_left : Icons.chevron_right,
                size: 18,
                color: cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool wideEnough =
        MediaQuery.sizeOf(context).width >= AppSize.chatSidebarMinWidth;
    final bool showSidebar =
        landscape && wideEnough && widget.controller.settings.chatQuickSidebar;

    // 收起/展开是**一条动画**驱动的:它同时决定侧栏浮层的宽度与聊天
    // 内容的内缩量,所以两列是滑出去/滑进来的,内容也跟着让位。
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
        _lastInset = inset;
        // 视图实例在这里取一次，动画帧里不再重新构造（见 [_viewFor]）。
        final Widget currentView = _viewFor(_conversationId, inset);
        return AnimatedBuilder(
          animation: _settleAnim,
          builder: (BuildContext context, Widget? _) {
            return ValueListenableBuilder<double>(
              valueListenable: _dragNotifier,
              builder: (BuildContext context, double dragDx, Widget? _) {
                final bool committing = _outgoingView != null;
                // 弹回时没有退场层，当前视图自己跟着 settle 曲线回去；
                // 提交切换时新视图直接归位(0)，旧视图滑出。
                final bool bouncing =
                    !committing && _settleAnim.isAnimating && _animTo == 0;
                final double viewDx = committing
                    ? 0
                    : (bouncing
                          ? _animFrom + (_animTo - _animFrom) * _settleT
                          : dragDx);
                // 预览来自 [_peekFor]，同样复用实例，不重建。
                final Widget? peek = committing
                    ? null
                    : _peekFor(context, offset: dragDx);
                return Stack(
              children: <Widget>[
                // 拖动中露出的"下一页"预览(提交后由新会话视图接管)。
                if (peek != null)
                  Positioned.fill(child: RepaintBoundary(child: peek)),
                // 当前会话(拖动时跟手平移)。RepaintBoundary 让平移只动图层，
                // 不重画整页内容。
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(viewDx, 0),
                    child: RepaintBoundary(child: currentView),
                  ),
                ),
                // 退场中的旧会话:滑出或淡出,期间不接收点击。
                if (_outgoingView != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: _outgoingMode == _OutgoingMode.fade
                            ? 1 - _settleT
                            : 1,
                        child: Transform.translate(
                          offset: Offset(
                            _outgoingMode == _OutgoingMode.slide
                                ? _animFrom + (_animTo - _animFrom) * _settleT
                                : 0,
                            0,
                          ),
                          child: _outgoingView,
                        ),
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
          },
        );
      },
    );
  }
}
/// 只在**横向明显占优**时才接受拖动的手势识别器。
///
/// Flutter 自带的 [HorizontalDragGestureRecognizer] 只看横向位移:手指
/// 上下滚动列表时,只要横向漂移超过命中容差,它就会把手势抢走 ——
/// 于是"上下滑动有时会触发左右切换"。这里先比方向:
/// * 横向位移 ≥ 纵向的 [_dominance] 倍 ⇒ 判定为横滑,交给父类竞争;
/// * 纵向已经超过命中容差 ⇒ 直接退出,把手势让给列表滚动。
///
/// 未判定前不参与(不把位移喂给父类),避免它在方向未明时就接受。
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
class ChatConversationView extends StatefulWidget {
  const ChatConversationView({
    super.key,
    required this.controller,
    required this.conversationId,
    this.isGroup = false,
    this.contentLeftInset = 0,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
  });

  final AppController controller;
  final String conversationId;
  final bool isGroup;

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
    // 「添加群成员」是一次多选任务（可能很长的名单），不是需要模态阻断的决定：
    // 用可滚动的大 sheet + 搜索，而不是把多选列表塞进 AlertDialog（审计 3.2）。
    // 返回语义不变：确认回传选中的 id 列表，取消/下滑关闭回传 null。
    final List<String>? updated = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        List<TA> visible = candidates;
        return Theme(
          data: _accentTheme,
          child: StatefulBuilder(
            builder:
                (
                  BuildContext sheetContext,
                  void Function(void Function()) setSheet,
                ) {
                  final ThemeData theme = Theme.of(sheetContext);
                  final ColorScheme cs = theme.colorScheme;
                  return Padding(
                    // 键盘避让：搜索框聚焦时整块抬到键盘上方。
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.sizeOf(sheetContext).height * 0.85,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: FitText(
                                    '添加群成员',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (selected.isNotEmpty)
                                  FitText(
                                    '已选 ${selected.length}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: cs.primary),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: '搜索名字',
                                prefixIcon: Icon(Icons.search),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (String value) {
                                final String keyword = value.trim();
                                setSheet(() {
                                  visible = keyword.isEmpty
                                      ? candidates
                                      : candidates
                                            .where(
                                              (TA t) =>
                                                  t.name.contains(keyword),
                                            )
                                            .toList();
                                });
                              },
                            ),
                          ),
                          AppSpacing.hMd,
                          Flexible(
                            child: visible.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.xl,
                                    ),
                                    child: Center(
                                      child: FitText(
                                        '没有匹配的名字',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: visible.length,
                                    itemBuilder:
                                        (
                                          BuildContext context,
                                          int index,
                                        ) {
                                          final TA ta = visible[index];
                                          return CheckboxListTile(
                                            value: selected.contains(
                                              ta.id,
                                            ),
                                            title: FitText(
                                              ta.name.isEmpty
                                                  ? '未命名TA'
                                                  : ta.name,
                                            ),
                                            onChanged: (bool? value) {
                                              setSheet(() {
                                                if (value == true) {
                                                  selected.add(ta.id);
                                                } else {
                                                  selected.remove(ta.id);
                                                }
                                              });
                                            },
                                          );
                                        },
                                  ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.md,
                              AppSpacing.lg,
                              AppSpacing.lg +
                                  MediaQuery.viewPaddingOf(
                                    sheetContext,
                                  ).bottom,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
                                    child: const FitText('取消'),
                                  ),
                                ),
                                AppSpacing.wMd,
                                Expanded(
                                  child: FilledButton(
                                    onPressed: selected.isEmpty
                                        ? null
                                        : () => Navigator.of(
                                            sheetContext,
                                          ).pop(selected.toList()),
                                    child: const FitText('添加'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
              // 60 而不是 56：选中态外圈描边（2 内边距 + 2 描边）会让单项
              // 高 4px，56 时正好溢出 2px（RenderFlex overflow）。
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tas.length,
                separatorBuilder: (_, int index) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final TA ta = tas[index];
                  final bool active = ta.id == _activeTaId;
                  final ImageProvider? avatar = _avatarForTa(ta);
                  // 发言者选择：既是"可点的目标"也是"当前选中的一项"，
                  // 所以要有涟漪、按钮语义与 selected 语义，且选中态不能只靠
                  // 底色（审计 4.3「只用颜色表达状态」）。外圈描边是非颜色冗余。
                  return Semantics(
                    button: true,
                    selected: active,
                    label: ta.name.isNotEmpty ? ta.name : '未命名TA',
                    hint: active ? '当前发言者' : '点击让它发言',
                    child: InkWell(
                      borderRadius: AppRadius.smAll,
                      onTap: () => _triggerTaReply(ta),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: active
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    )
                                  : null,
                              child: CircleAvatar(
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
                      ),
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
                  // 沉浸入口收进 ⋮ 菜单（顶栏回到 3 个动作，见 R5）。
                  immersiveHidden: _immersiveUiHidden,
                  onToggleImmersive: _toggleImmersive,
                ),
        ),
      ),
      // 点空白只负责收键盘；沉浸态的退出走屏幕上那颗可见按钮
      // （不再用「点上半区空白」这种隐形热区，也不再用「点任意位置退出」
      // 当第二套入口）。
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
            // 沉浸态的唯一常驻控件：可见的退出入口，替换原来的隐形热区。
            if (_immersiveUiHidden)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: IconButton.filledTonal(
                      onPressed: _toggleImmersive,
                      tooltip: '退出沉浸',
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ),
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
