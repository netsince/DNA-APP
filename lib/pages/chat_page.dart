import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../utils/conversation_labels.dart';
import '../models/conversation.dart';
import '../models/ta.dart';
import '../services/resume_service.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/fit_text.dart';
import '../widgets/ta_avatar.dart';
import 'chat/chat_surface.dart';

part 'chat/ui/chat_quick_sidebar.dart';

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
    return ChatSurface(
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
  /// 重新构造 ChatSurface，整棵消息列表都会被 build 一遍。
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
