part of '../../chat_page.dart';

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

/// 聊天页左侧的**快速切换侧栏**(横屏宽窗口)。
///
/// 两级选择:
/// * 左列 = 角色 1:1 头像,按「我家」的自定义顺序排列,**只列有
///   非归档 1:1 会话的角色**;点它只切换右列内容,**不切聊天**;
/// * 右列 = 该角色的聊天(注释 = 备注,或最后一条用户消息前 5 字),
///   点它才真正切换会话。
///
/// 两列各自独立滚动,行高固定,所以"滚动到当前项"可以直接按索引算
/// 偏移,不依赖条目是否已经构建(列表长时也不会定位失败)。
class ChatQuickSidebar extends StatefulWidget {
  const ChatQuickSidebar({
    super.key,
    required this.controller,
    required this.currentConversationId,
    required this.onSelectConversation,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final AppController controller;

  /// 当前正在看的会话(用于高亮 + 进入时自动定位)。
  final String currentConversationId;

  /// 点右列某条聊天:交给外层**原地换会话**。
  final ValueChanged<String> onSelectConversation;

  /// 收起状态由外层持有:切换会话时不会丢。
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final List<TA> characters = _characters();
        final String? taId = _effectiveTaId(characters);
        final List<Conversation> chats = _chatsOf(taId);
        return Material(
          color: colorScheme.surfaceContainerLow,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHandle(context),
              if (!widget.collapsed) ...<Widget>[
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
            ],
          ),
        );
      },
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
            icon: Icon(
              widget.collapsed ? Icons.chevron_right : Icons.chevron_left,
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
              child: Container(
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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    if (taId == null) {
      return _buildHint(context, '选择一个角色');
    }
    if (chats.isEmpty) {
      return _buildHint(context, '这个角色还没有聊天');
    }
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
          child: Material(
            color: current ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
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
