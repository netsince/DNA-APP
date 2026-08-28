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
  String? _lastAccentMode;
  int? _lastCustomAccentColor;
  

  // 缓存图片 provider 避免重复创建
  final Map<String, ImageProvider> _imageCache = <String, ImageProvider>{};

  bool get _sending => _state.sending;
  set _sending(bool value) => _state.sending = value;
  bool get _generationStopRequested => _state.generationStopRequested;
  set _generationStopRequested(bool value) => _state.generationStopRequested = value;

  /// 输入条「停止」按钮回调:请求中断当前流式生成。
  /// 实际中断发生在消费循环的下一次迭代(break 取消订阅,连接随之终止)。
  void requestStopGeneration() => _generationStopRequested = true;
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

    // 记录当前 accent 设置，用于检测设置页切换后实时刷新聊天页取色。
    _lastAccentMode = widget.controller.settings.accentMode;
    _lastCustomAccentColor = widget.controller.settings.customAccentColor;
    widget.controller.addListener(_onSettingsChanged);
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

    // 进入聊天页：同步背景音乐音量并启动角色背景音乐（仅单聊、开启时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureBgm();
    });

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
    widget.controller.removeListener(_onSettingsChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _imageCache.clear();
    // 离开聊天页停止背景音乐，避免残留播放
    _stopBgm();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用切后台时暂停背景音乐，回前台恢复（若仍开启且该角色有音乐）。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      BgmPlayer.instance.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_bgmEnabled && !_isGroup) {
        final String? musicPath = _ta?.musicPath;
        if (musicPath != null && musicPath.isNotEmpty) {
          BgmPlayer.instance.resume();
        }
      }
    }
  }

  /// 是否播放当前角色背景音乐（三点菜单切换）。默认开启。
  bool _bgmEnabled = true;

  /// 同步背景音乐音量，并在满足条件时启动当前角色的音乐。
  Future<void> _ensureBgm() async {
    final AppSettings s = widget.controller.settings;
    BgmPlayer.instance.setBaseVolume(s.bgmVolume / 100.0);
    if (_bgmEnabled && !_isGroup) {
      final String? musicPath = _ta?.musicPath;
      if (musicPath != null && musicPath.isNotEmpty) {
        await BgmPlayer.instance.play(musicPath);
      }
    }
  }

  /// 停止背景音乐（离开聊天页 / 切到群聊）。
  void _stopBgm() {
    BgmPlayer.instance.stop();
  }

  /// 三点菜单：切换是否播放背景音乐。
  Future<void> _toggleBgm() async {
    _bgmEnabled = !_bgmEnabled;
    if (!mounted) return;
    setState(() {});
    if (_bgmEnabled) {
      await _ensureBgm();
    } else {
      BgmPlayer.instance.stop();
    }
  }

  // 设置页切换 accent 模式/颜色后，实时刷新聊天页取色
  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }
    final AppSettings s = widget.controller.settings;
    if (s.accentMode != _lastAccentMode || s.customAccentColor != _lastCustomAccentColor) {
      _lastAccentMode = s.accentMode;
      _lastCustomAccentColor = s.customAccentColor;
      _loadAccent();
    }
  }

  // 把 colorScheme.primary 系列替换为当前角色取色（_accent），供底部输入栏与
  // 子页面弹框使用；无取色时回退到默认主题。
  ThemeData get _accentTheme {
    final ThemeData base = Theme.of(context);
    final Color? accent = _accent;
    if (accent == null) {
      return base;
    }
    final Color onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: onAccent,
        primaryContainer:
            Color.alphaBlend(accent.withValues(alpha: 0.16), base.colorScheme.surface),
        onPrimaryContainer: accent,
      ),
    );
  }

  // 缓存图片 provider（跨平台：IO 走文件，Web 走 IndexedDB）
  ImageProvider? _getCachedImage(String path) {
    if (!_imageCache.containsKey(path)) {
      final ImageProvider? provider =
          ImageStorage.instance.providerForRef(path);
      if (provider == null) {
        return null;
      }
      _imageCache[path] = provider;
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
