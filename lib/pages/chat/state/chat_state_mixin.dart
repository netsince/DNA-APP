part of '../../chat_page.dart';

mixin ChatStateMixin on State<ChatPage>, WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  // 记录上一次键盘是否处于展开状态，用于检测「键盘被收起」的时刻
  bool _keyboardWasOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final ChatState _state = ChatState();
  late final ChatController _chatController;
  late Conversation _conversation;
  Color? _accent;
  
  // 缓存图片 provider 避免重复创建
  final Map<String, ImageProvider> _imageCache = <String, ImageProvider>{};

  bool get _sending => _state.sending;
  set _sending(bool value) => _state.sending = value;
  bool get _searching => _state.searching;
  set _searching(bool value) => _state.searching = value;
  bool get _showTokenCounts => _state.showTokenCounts;
  set _showTokenCounts(bool value) => _state.showTokenCounts = value;
  int get _searchMatchIndex => _state.searchMatchIndex;
  set _searchMatchIndex(int value) => _state.searchMatchIndex = value;
  Map<String, GlobalKey> get _messageKeys => _state.messageKeys;
  final ChatTokenCounter _tokenCounter = ChatTokenCounter();
  final ChatSnapshotStore _snapshotStore = ChatSnapshotStore();
  bool get _summaryInProgress => _state.summaryInProgress;
  set _summaryInProgress(bool value) => _state.summaryInProgress = value;
  int get _summaryTaskId => _state.summaryTaskId;
  set _summaryTaskId(int value) => _state.summaryTaskId = value;
  int? get _cancelledSummaryTaskId => _state.cancelledSummaryTaskId;
  set _cancelledSummaryTaskId(int? value) => _state.cancelledSummaryTaskId = value;
  PendingSummary? get _pendingSummary => _state.pendingSummary;
  set _pendingSummary(PendingSummary? value) => _state.pendingSummary = value;
  bool get _rangeSummaryInProgress => _state.rangeSummaryInProgress;
  set _rangeSummaryInProgress(bool value) => _state.rangeSummaryInProgress = value;
  bool get _inspirationInProgress => _state.inspirationInProgress;
  set _inspirationInProgress(bool value) => _state.inspirationInProgress = value;
  String get _inspirationPrompt => _state.inspirationPrompt;
  set _inspirationPrompt(String value) => _state.inspirationPrompt = value;
  List<String> get _inspirationOptions => _state.inspirationOptions;
  Map<String, ThoughtEntry> get _thoughtsByMessageId => _state.thoughtsByMessageId;
  Map<String, StreamParseState> get _streamParseStates => _state.streamParseStates;
  Map<String, List<String>> get _retryAlternatives => _state.retryAlternatives;
  Set<String> get _retryDisabled => _state.retryDisabled;
  // ignore: unused_element
  Set<String> get _visibleThoughtMessageIds => _state.visibleThoughtMessageIds;

  bool get _isGroup => _conversation.isGroup || widget.isGroup;
  
  String get _activeTaId {
    final String? active = _conversation.activeTaId;
    if (active != null && active.isNotEmpty) {
      return active;
    }
    return _conversation.taId;
  }
  
  TA? get _activeTa => widget.controller.getTaById(_activeTaId);
  
  List<String> get _memberTaIds =>
      _conversation.memberTaIds.isNotEmpty ? _conversation.memberTaIds : <String>[_conversation.taId];
  
  List<TA> get _memberTas => _memberTaIds
      .map(widget.controller.getTaById)
      .whereType<TA>()
      .toList();
      
  TA? get _ta => _isGroup ? _activeTa : widget.controller.getTaById(_conversation.taId);
  
  World? get _world => widget.controller.getWorldById(_conversation.worldId);

  Future<void> _ensureOpeningMessage();
  Future<void> _loadAccent();
  void _scrollToBottom();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatController = ChatController(scrollController: _scrollController);
    Conversation? existing;
    if (widget.isGroup) {
      existing = widget.controller.getGroupById(widget.conversationId);
    } else {
      for (final Conversation c in widget.controller.conversations) {
        if (c.id == widget.conversationId) {
          existing = c;
          break;
        }
      }
    }
    _conversation = existing ??
        Conversation(
          id: widget.conversationId,
          taId: '',
          worldId: null,
          note: '',
          messages: const <ConversationMessage>[],
          backgroundMode: 'none',
          summaries: const <ConversationSummary>[],
          archived: false,
          isGroup: widget.isGroup,
          groupName: '',
          groupPrompt: '',
          memberTaIds: const <String>[],
          activeTaId: null,
        );
    _ensureGroupDefaults();
    _ensureOpeningMessage();

    // 延迟加载 accent 避免阻塞 initState
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _loadAccent();
      }
    });

    // 确保页面加载后滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    // 延迟再次滚动，确保消息列表渲染完成后滚动到底部
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _imageCache.clear();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 键盘弹出/收起会逐帧改变视口高度（viewInsets）。键盘动画进行中滚动会滚到
    // 过时的底部位置，落下几个像素；改为在每帧布局完成后再滚动，待键盘稳定时
    // 即滚到真正的底部。仅在键盘展开（聚焦输入）时滚动，避免打断历史浏览。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final bool keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
      if (keyboardOpen) {
        _keyboardWasOpen = true;
        _scrollToBottom();
      } else {
        // 键盘从展开变为收起（含使用键盘自带收起按钮的情况）。此时 Flutter 不会
        // 自动清除输入框焦点，需主动收焦，避免焦点残留导致后续行为异常。
        if (_keyboardWasOpen && _inputFocusNode.hasFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        _keyboardWasOpen = false;
      }
    });
  }

  // 缓存图片 provider
  ImageProvider? _getCachedImage(String path) {
    if (!_imageCache.containsKey(path)) {
      final File file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      _imageCache[path] = FileImage(file);
    }
    return _imageCache[path];
  }

  Future<void> _ensureGroupDefaults() async {
    if (!_isGroup) {
      return;
    }
    final List<String> uniqueMembers = <String>[
      if (_conversation.taId.isNotEmpty) _conversation.taId,
      ..._conversation.memberTaIds.where((String id) => id != _conversation.taId),
    ];
    String? active = _conversation.activeTaId;
    if (active == null || active.isEmpty) {
      active = uniqueMembers.isNotEmpty ? uniqueMembers.first : _conversation.taId;
    } else if (uniqueMembers.isNotEmpty && !uniqueMembers.contains(active)) {
      active = uniqueMembers.first;
    }
    _conversation = _conversation.copyWith(
      isGroup: true,
      memberTaIds: uniqueMembers,
      activeTaId: active,
    );
    await widget.controller.upsertGroupConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
}
