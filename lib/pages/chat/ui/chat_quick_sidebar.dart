part of '../../chat_page.dart';

/// 侧栏展开时的总宽度:把手 + 角色列 + 分隔线 + 聊天列。
const double kChatSidebarFullWidth =
    AppSize.chatSidebarHandle +
    AppSize.chatSidebarAvatarColumn +
    1 +
    AppSize.chatSidebarListWidth;

/// 侧栏里一条聊天的「注释」文案。
///
/// 规则(与用户确认):**备注优先**;没有备注就用该会话里**最后一条
/// 用户消息的前 5 个字 + 省略号**(不足 5 个字不加省略号)。
/// 一条用户消息都没有时给「新对话」。
String chatSidebarAnnotation(Conversation conversation) {
  final String note = conversation.note.trim();
  if (note.isNotEmpty) {
    return note;
  }
  for (int i = conversation.messages.length - 1; i >= 0; i--) {
    final ConversationMessage message = conversation.messages[i];
    if (message.role != 'user') {
      continue;
    }
    // 换行/连续空白压成单空格,免得注释里出现折行空洞。
    final String text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      continue;
    }
    final Characters chars = text.characters;
    final String head = chars.take(5).toString();
    return chars.length > 5 ? '$head…' : head;
  }
  return '新对话';
}

/// 聊天页左侧的**快速切换侧栏**(横屏宽窗口),以磨砂浮层的形式盖在
/// 聊天视图之上。
///
/// 两级选择:
/// * 左列 = 角色 1:1 头像,按「我家」的自定义顺序排列,**只列有
///   非归档 1:1 会话的角色**;点它只切换右列内容,**不切聊天**;
/// * 右列 = 该角色的聊天(注释 = 备注,或最后一条用户消息前 5 字),
///   点它才真正切换会话。
///
/// ## 为什么是浮层而不是并排的一列
///
/// 浮层盖在**全宽的聊天视图**上,于是角色背景立绘会一直铺到侧栏底下,
/// 侧栏用「半透明 + 高斯模糊」把它虚化透出来 —— 与气泡透出背景是
/// 同一套设计语言,不会出现一块和背景无关的死板色块。
/// 聊天内容则按侧栏宽度整体内缩(见 `ChatConversationView.contentLeftInset`),
/// 所以浮层不会压住消息。
///
/// ## 收起/展开
///
/// 宽度由外层动画驱动([width]):内部内容始终保持满宽,由 [ClipRect]
/// 裁掉右侧 —— 收起时两列是"滑出去"的,不是瞬间消失。
class ChatQuickSidebar extends StatefulWidget {
  const ChatQuickSidebar({
    super.key,
    required this.controller,
    required this.currentConversationId,
    required this.onSelectConversation,
    required this.width,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final AppController controller;

  /// 当前正在看的会话(用于高亮 + 进入时自动定位)。
  final String currentConversationId;

  /// 点右列某条聊天:交给外层**原地换会话**。
  final ValueChanged<String> onSelectConversation;

  /// 动画宽度(收起时 = 把手宽度)。
  final double width;

  /// 是否处于收起状态(决定把手箭头方向与提示)。
  final bool collapsed;

  final VoidCallback onToggleCollapsed;

  @override
  State<ChatQuickSidebar> createState() => _ChatQuickSidebarState();
}

class _ChatQuickSidebarState extends State<ChatQuickSidebar> {
  final ScrollController _characterScroll = ScrollController();
  final ScrollController _chatScroll = ScrollController();

  /// 左列选中的角色(只影响右列显示,不影响正在看的会话)。
  String? _selectedTaId;

  @override
  void initState() {
    super.initState();
    _selectedTaId = _taIdOfCurrentConversation();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(ChatQuickSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentConversationId != widget.currentConversationId) {
      // 跟随当前路径:切到某个角色的聊天后,左列选中它。
      final String? taId = _taIdOfCurrentConversation();
      if (taId != null) {
        _selectedTaId = taId;
      }
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _characterScroll.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealCurrent();
      }
    });
  }

  // ---------- 数据 ----------

  Conversation? _conversationById(String id) {
    for (final Conversation conversation in widget.controller.conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  /// 当前会话所属角色(群聊返回 null —— 侧栏不含群聊)。
  String? _taIdOfCurrentConversation() {
    final Conversation? current = _conversationById(
      widget.currentConversationId,
    );
    if (current == null || current.isGroup) {
      return null;
    }
    return current.taId;
  }

  /// 左列:按「我家」顺序,只保留有非归档 1:1 会话的角色。
  List<TA> _characters() {
    final Set<String> withChats = <String>{
      for (final Conversation conversation in widget.controller.conversations)
        if (!conversation.isGroup && !conversation.archived) conversation.taId,
    };
    return <TA>[
      for (final TA ta in widget.controller.tas)
        if (withChats.contains(ta.id)) ta,
    ];
  }

  /// 右列:该角色的非归档 1:1 会话,置顶优先,其余按最近消息在前。
  ///
  /// 会话模型没有"更新时间"字段,只能从消息列表末条取时间。
  List<Conversation> _chatsOf(String? taId) {
    if (taId == null) {
      return const <Conversation>[];
    }
    final List<Conversation> chats = <Conversation>[
      for (final Conversation conversation in widget.controller.conversations)
        if (!conversation.isGroup &&
            !conversation.archived &&
            conversation.taId == taId)
          conversation,
    ];
    chats.sort((Conversation a, Conversation b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return _lastTimestamp(b).compareTo(_lastTimestamp(a));
    });
    return chats;
  }

  static int _lastTimestamp(Conversation conversation) =>
      conversation.messages.isEmpty ? 0 : conversation.messages.last.timestamp;

  /// 实际生效的选中角色:原选中角色若已无聊天(被删/归档),回退到第一个。
  String? _effectiveTaId(List<TA> characters) {
    final String? selected = _selectedTaId;
    if (selected != null && characters.any((TA ta) => ta.id == selected)) {
      return selected;
    }
    return characters.isEmpty ? null : characters.first.id;
  }

  // ---------- 滚动定位 ----------

  void _revealCurrent() {
    final List<TA> characters = _characters();
    final String? taId = _effectiveTaId(characters);
    _reveal(
      _characterScroll,
      characters.indexWhere((TA ta) => ta.id == taId),
      AppSize.chatSidebarAvatarExtent,
    );
    final List<Conversation> chats = _chatsOf(taId);
    _reveal(
      _chatScroll,
      chats.indexWhere(
        (Conversation c) => c.id == widget.currentConversationId,
      ),
      AppSize.chatSidebarChatExtent,
    );
  }

  /// 把第 [index] 项滚到视口中间(行高固定,直接算偏移)。
  static void _reveal(ScrollController controller, int index, double extent) {
    if (index < 0 || !controller.hasClients) {
      return;
    }
    final double viewport = controller.position.viewportDimension;
    final double target = index * extent - (viewport - extent) / 2;
    controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
  }

  // ---------- 渲染 ----------

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: ClipRect(
        // 磨砂:虚化盖在下方的角色背景立绘。
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          // Material 提供水波纹的"材质"面:侧栏是浮层,外面不一定有
          // Material 祖先(InkWell 会直接报错),所以自己带一个;
          // 底色用半透明,配合上面的模糊透出底下的角色立绘。
          child: Material(
            color: colorScheme.surface.withValues(alpha: 0.72),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              // 内容保持满宽、靠左对齐:宽度收窄时右侧被裁掉 ⇒ 两列"滑出去"。
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: kChatSidebarFullWidth,
                maxWidth: kChatSidebarFullWidth,
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (BuildContext context, Widget? _) {
                    final List<TA> characters = _characters();
                    final String? taId = _effectiveTaId(characters);
                    final List<Conversation> chats = _chatsOf(taId);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildHandle(context),
                        SizedBox(
                          width: AppSize.chatSidebarAvatarColumn,
                          child: _buildCharacters(context, characters, taId),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: AppSize.chatSidebarListWidth,
                          child: _buildChats(context, chats, taId),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 收起/展开把手:始终可见,位置固定,不会随内容滚动跑掉。
  Widget _buildHandle(BuildContext context) {
    return SizedBox(
      width: AppSize.chatSidebarHandle,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: IconButton(
            tooltip: widget.collapsed ? '展开快速切换栏' : '收起快速切换栏',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: widget.onToggleCollapsed,
            icon: AnimatedRotation(
              turns: widget.collapsed ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: const Icon(Icons.chevron_left),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCharacters(
    BuildContext context,
    List<TA> characters,
    String? selectedTaId,
  ) {
    if (characters.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: _characterScroll,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemExtent: AppSize.chatSidebarAvatarExtent,
      itemCount: characters.length,
      itemBuilder: (BuildContext context, int index) {
        final TA ta = characters[index];
        final bool selected = ta.id == selectedTaId;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Tooltip(
            message: ta.name.trim().isEmpty ? '未命名TA' : ta.name,
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              // 点角色只换右列内容,不切聊天(两级选择的第一步)。
              onTap: () => setState(() => _selectedTaId = ta.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? colorScheme.primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: TaAvatar(ta: ta, size: 32, borderRadius: 8),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChats(
    BuildContext context,
    List<Conversation> chats,
    String? taId,
  ) {
    if (taId == null) {
      return _buildHint(context, '选择一个角色');
    }
    if (chats.isEmpty) {
      return _buildHint(context, '这个角色还没有聊天');
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // 换角色时整列淡入淡出,而不是硬切。
      child: KeyedSubtree(
        key: ValueKey<String>(taId),
        child: _buildChatList(context, chats),
      ),
    );
  }

  Widget _buildChatList(BuildContext context, List<Conversation> chats) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return ListView.builder(
      controller: _chatScroll,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemExtent: AppSize.chatSidebarChatExtent,
      itemCount: chats.length,
      itemBuilder: (BuildContext context, int index) {
        final Conversation conversation = chats[index];
        final bool current = conversation.id == widget.currentConversationId;
        final String label = chatSidebarAnnotation(conversation);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: current
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => widget.onSelectConversation(conversation.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    if (conversation.pinned) ...<Widget>[
                      Icon(
                        Icons.push_pin,
                        size: 12,
                        color: current
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Tooltip(
                        message: label,
                        waitDuration: const Duration(milliseconds: 400),
                        child: FitText(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: current
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                            fontWeight: current
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHint(BuildContext context, String text) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: FitText(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
        ),
      ),
    );
  }
}
