part of '../../chat_page.dart';

mixin ChatStateMixin on State<ChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final ChatState _state = ChatState();
  late final ChatController _chatController;
  late Conversation _conversation;
  Color? _accent;
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
    _loadAccent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
