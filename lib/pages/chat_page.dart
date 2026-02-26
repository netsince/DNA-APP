import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tiktoken/tiktoken.dart';
import '../utils/id_utils.dart';
import '../models/conversation.dart';
import '../models/dialogue_style.dart';
import '../models/role.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.conversationId});
  final AppController controller;
  final String conversationId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}
class _ChatPageState extends State<ChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late Conversation _conversation;
  Color? _accent;
  bool _sending = false;
  bool _searching = false;
  bool _showTokenCounts = false;
  int _searchMatchIndex = -1;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, _TokenCacheEntry> _tokenCache = <String, _TokenCacheEntry>{};
  Encoding? _tokenEncoding;
  String? _tokenEncodingModel;
  final Map<String, List<String>> _retryAlternatives = <String, List<String>>{};
  final Set<String> _retryDisabled = <String>{};
  static const String _snapshotKeyPrefix = 'conversation_snapshots_v1_';
  @override
  void initState() {
    super.initState();
    Conversation? existing;
    for (final Conversation c in widget.controller.conversations) {
      if (c.id == widget.conversationId) {
        existing = c;
        break;
      }
    }
    _conversation = existing ??
        Conversation(
          id: widget.conversationId,
          roleId: '',
          worldId: null,
          note: '',
          messages: const <ConversationMessage>[],
          backgroundMode: 'none',
        );
    _ensureOpeningMessage();
    _loadAccent();
  }
  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
  Role? get _role => widget.controller.getRoleById(_conversation.roleId);
  World? get _world => widget.controller.getWorldById(_conversation.worldId);
  Future<void> _ensureOpeningMessage() async {
    if (_conversation.messages.isNotEmpty) {
      return;
    }
    final Role? role = _role;
    if (role == null || role.opening.trim().isEmpty) {
      return;
    }
    final ConversationMessage opening = ConversationMessage(
      id: newId(),
      role: 'assistant',
      text: role.opening.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _conversation = _conversation.copyWith(messages: <ConversationMessage>[opening]);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<void> _loadAccent() async {
    final Role? role = _role;
    final String? path = role?.images['square'];
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return;
    }
    final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
      FileImage(File(path)),
      size: const Size(128, 128),
      maximumColorCount: 8,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _accent = palette.dominantColor?.color;
    });
  }
  Future<void> _send() async {
    final String text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (_sending) {
      return;
    }
    final Role? role = _role;
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色不存在，请重新创建会话。')),
      );
      return;
    }
    if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中完成 API 与模型配置。')),
      );
      return;
    }
    final ConversationMessage userMessage = ConversationMessage(
      id: newId(),
      role: 'user',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _inputController.clear();
    final List<ConversationMessage> updated = <ConversationMessage>[..._conversation.messages, userMessage];
    _conversation = _conversation.copyWith(messages: updated);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    setState(() => _sending = true);
    final String assistantId = newId();
    ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[..._conversation.messages, assistantMessage],
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    await for (final String chunk in widget.controller.openAiService.streamChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: _buildMessages(),
    )) {
      if (!mounted) {
        return;
      }
      if (chunk.startsWith('[ERROR]')) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chunk.replaceFirst('[ERROR] ', ''))),
        );
        return;
      }
      assistantMessage = assistantMessage.copyWith(text: assistantMessage.text + chunk);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          assistantMessage,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
  }
  String _buildSystemPrompt() {
    final Role? role = _role;
    final World? world = _world;
    final List<DialogueTurn> style = role?.dialogueStyle ?? <DialogueTurn>[];
    final StringBuffer system = StringBuffer();
    system.writeln('你是“角色扮演对话”模式。必须严格遵守以下规则：');
    system.writeln('1) 括号“（…）”为旁白，只用于动作、表情、内心或环境描写，且尽量简短。');
    system.writeln('2) 每次回复只写一句话，不换行、不分段，不使用多句并列。');
    system.writeln('3) “**…**”仅用于音效/环境声/拟声。');
    system.writeln('4) 不写故事片段，不展开叙事，不总结背景，不进行长篇描写。');
    system.writeln('5) 必须紧跟用户意图与上一句对话推进互动：要么回应，要么提一个简短问题。');
    system.writeln('6) 不替用户决定行动，不抢戏，不替用户续写其内心。');
    system.writeln('7) 严格保持角色人设与语气：只以角色身份说话，不跳出角色、不评价自己。');
    system.writeln('8) 设定冲突优先级：人设 > 世界观 > 对话风格 > 常识；发生冲突时以高优先级为准。');
    system.writeln('9) 角色已知设定优先于常识推理；设定缺失时用最符合角色的方式简短补齐，避免自相矛盾。');
    system.writeln('10) 避免解释规则与自我说明，不提“模型/AI/系统/提示词”等词。');
    system.writeln('11) 语言简洁，优先口语化，长度尽量控制在20~60字内。');
    if (role != null) {
      if (role.persona.isNotEmpty) {
        system.writeln('人设：${role.persona}');
      }
      if (role.intro.isNotEmpty) {
        system.writeln('介绍：${role.intro}');
      }
    }
    if (world != null) {
      if (world.summary.isNotEmpty) {
        system.writeln('世界：${world.summary}');
      } else if (world.description.isNotEmpty) {
        system.writeln('世界：${world.description}');
      }
    }
    if (style.isNotEmpty) {
      system.writeln('对话风格：');
      for (final DialogueTurn turn in style) {
        if (turn.user.trim().isNotEmpty) {
          system.writeln('我：${turn.user.trim()}');
        }
        if (turn.assistant.trim().isNotEmpty) {
          system.writeln('你：${turn.assistant.trim()}');
        }
      }
    }
    return system.toString().trim();
  }
  List<Map<String, String>> _buildMessagesFrom(
    List<ConversationMessage> messages, {
    String? extraUserText,
  }) {
    final List<Map<String, String>> payload = <Map<String, String>>[];
    final String sys = _buildSystemPrompt();
    if (sys.isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': sys});
    }
    for (final ConversationMessage message in messages) {
      payload.add(<String, String>{
        'role': message.role,
        'content': message.text,
      });
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }
  List<Map<String, String>> _buildMessages() {
    return _buildMessagesFrom(_conversation.messages);
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleSearch() {
    final bool next = !_searching;
    setState(() {
      _searching = next;
      if (!next) {
        _searchController.clear();
        _searchMatchIndex = -1;
      }
    });
    if (next) {
      _updateSearch(_searchController.text);
    }
  }

  void _updateSearch(String raw) {
    final String query = raw.trim();
    final List<int> matches = _computeSearchMatches(query);
    if (query.isEmpty) {
      setState(() => _searchMatchIndex = -1);
      return;
    }
    setState(() {
      _searchMatchIndex = matches.isEmpty ? -1 : 0;
    });
    if (_searchMatchIndex >= 0) {
      _jumpToMessageIndex(matches[_searchMatchIndex]);
    }
  }

  List<int> _computeSearchMatches(String query) {
    if (query.isEmpty) {
      return <int>[];
    }
    final String lowerQuery = query.toLowerCase();
    final List<int> matches = <int>[];
    for (int i = 0; i < _conversation.messages.length; i++) {
      final String text = _conversation.messages[i].text;
      if (text.toLowerCase().contains(lowerQuery)) {
        matches.add(i);
      }
    }
    return matches;
  }

  void _navigateMatch(int delta) {
    final String query = _searchController.text.trim();
    final List<int> matches = _computeSearchMatches(query);
    if (matches.isEmpty) {
      setState(() => _searchMatchIndex = -1);
      return;
    }
    final int nextIndex = _searchMatchIndex < 0
        ? 0
        : (((_searchMatchIndex + delta) % matches.length) + matches.length) % matches.length;
    setState(() => _searchMatchIndex = nextIndex);
    _jumpToMessageIndex(matches[nextIndex]);
  }

  void _jumpToMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _conversation.messages.length) {
      return;
    }
    final String id = _conversation.messages[messageIndex].id;
    final GlobalKey? key = _messageKeys[id];
    if (key == null || key.currentContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      key.currentContext!,
      alignment: 0.3,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Encoding _ensureEncoding() {
    final String model = widget.controller.settings.selectedModel;
    if (_tokenEncoding == null || _tokenEncodingModel != model) {
      try {
        _tokenEncoding = encodingForModel(model);
      } catch (_) {
        _tokenEncoding = getEncoding('cl100k_base');
      }
      _tokenEncodingModel = model;
      _tokenCache.clear();
    }
    return _tokenEncoding!;
  }

  int _countTokens(String messageId, String text) {
    final _TokenCacheEntry? cached = _tokenCache[messageId];
    if (cached != null && cached.text == text) {
      return cached.count;
    }
    if (text.isEmpty) {
      _tokenCache[messageId] = const _TokenCacheEntry(text: '', count: 0);
      return 0;
    }
    final Encoding encoding = _ensureEncoding();
    final int count = encoding.encode(text).length;
    _tokenCache[messageId] = _TokenCacheEntry(text: text, count: count);
    return count;
  }

  TextSpan _buildHighlightedText(BuildContext context, String text) {
    final String query = _searchController.text.trim();
    final TextStyle base = DefaultTextStyle.of(context).style;
    if (query.isEmpty) {
      return TextSpan(text: text, style: base);
    }
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    int start = 0;
    final List<InlineSpan> spans = <InlineSpan>[];
    while (true) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: base));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: base));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: base.copyWith(
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.55),
          ),
        ),
      );
      start = index + query.length;
    }
    return TextSpan(children: spans, style: base);
  }
  Future<List<_ChatSnapshot>> _loadSnapshots() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('$_snapshotKeyPrefix${_conversation.id}') ?? '';
    if (raw.isEmpty) {
      return <_ChatSnapshot>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(_ChatSnapshot.fromJson)
            .toList();
      }
    } catch (_) {}
    return <_ChatSnapshot>[];
  }
  Future<void> _saveSnapshots(List<_ChatSnapshot> snapshots) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(snapshots.map((s) => s.toJson()).toList());
    await prefs.setString('$_snapshotKeyPrefix${_conversation.id}', raw);
  }
  Future<void> _manageSnapshots() async {
    final List<_ChatSnapshot> snapshots = await _loadSnapshots();
    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('存档管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: snapshots.isEmpty
                ? const Text('暂无存档')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshots.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _ChatSnapshot snapshot = snapshots[index];
                      final DateTime time = DateTime.fromMillisecondsSinceEpoch(snapshot.timestamp);
                      return ListTile(
                        title: Text(snapshot.name),
                        subtitle: Text(time.toString().substring(0, 19)),
                        onTap: () => Navigator.of(context).pop('load:$index'),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('create'),
              child: const Text('新建存档'),
            ),
          ],
        );
      },
    );
    if (action == null) {
      return;
    }
    if (action == 'create') {
      final String defaultName = '存档 ${DateTime.now().toString().substring(0, 19)}';
      final TextEditingController controller = TextEditingController(text: defaultName);
      final String? name = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('创建存档'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入存档名称'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      snapshots.insert(
        0,
        _ChatSnapshot(
          id: newId(),
          name: name.trim(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          data: _conversation.toJson(),
        ),
      );
      await _saveSnapshots(snapshots);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('存档已保存。')),
      );
      return;
    }
    if (action.startsWith('load:')) {
      final int index = int.tryParse(action.split(':').last) ?? -1;
      if (index < 0 || index >= snapshots.length) {
        return;
      }
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('确认加载存档'),
            content: const Text('将覆盖当前对话并无法撤销，确定要继续吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshots[index].data);
      data['id'] = _conversation.id;
      _conversation = Conversation.fromJson(data);
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
  }
  Future<void> _showMessageMenu({
    required Offset position,
    required String text,
    required bool isAssistant,
    required int index,
  }) async {
    final RelativeRect anchor = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );
    final bool retryDisabled = _retryDisabled.contains(_conversation.messages[index].id);
    final bool canContinue = isAssistant && index == _conversation.messages.length - 1;
    final String? action = await showMenu<String>(
      context: context,
      position: anchor,
      items: <PopupMenuEntry<String>>[
        if (isAssistant)
          PopupMenuItem<String>(
            value: 'continue',
            enabled: canContinue,
            child: ListTile(
              leading: Icon(Icons.play_arrow),
              title: Text('继续说'),
            ),
          ),
        if (isAssistant)
          PopupMenuItem<String>(
            value: 'retry',
            enabled: !retryDisabled,
            child: const ListTile(
              leading: Icon(Icons.refresh),
              title: Text('重说'),
            ),
          ),
        if (isAssistant)
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('更改文字'),
            ),
          ),
        if (isAssistant)
          const PopupMenuItem<String>(
            value: 'rollback',
            child: ListTile(
              leading: Icon(Icons.undo),
              title: Text('回溯到此处'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy),
            title: Text('复制'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'share',
          child: ListTile(
            leading: Icon(Icons.share),
            title: Text('分享'),
          ),
        ),
      ],
    );
    if (action == null) {
      return;
    }
    if (action == 'continue') {
      await _continueFromContext();
      return;
    }
    if (action == 'retry') {
      await _retryAssistantAt(index);
      return;
    }
    if (action == 'edit') {
      await _editAssistantAt(index);
      return;
    }
    if (action == 'rollback') {
      await _rollbackTo(index);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
      return;
    }
    if (action == 'share') {
      await Share.share(text);
    }
  }
  Future<void> _continueFromContext() async {
    if (_sending) {
      return;
    }
    final Role? role = _role;
    if (role == null) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中完成 API 与模型配置。')),
      );
      return;
    }
    setState(() => _sending = true);
    final String assistantId = newId();
    ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[..._conversation.messages, assistantMessage],
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    final String sys = _buildSystemPrompt();
    final List<Map<String, String>> payload = <Map<String, String>>[];
    if (sys.isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': sys});
    }
    payload.add(<String, String>{
      'role': 'system',
      'content': '请继续上一条助手回复，延续语气，不要重复已说内容，不要引入新话题。',
    });
    payload.addAll(
      _conversation.messages
          .where((ConversationMessage m) => m.id != assistantId)
          .map((ConversationMessage m) => <String, String>{
                'role': m.role,
                'content': m.text,
              }),
    );
    await for (final String chunk in widget.controller.openAiService.streamChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: payload,
    )) {
      if (!mounted) {
        return;
      }
      if (chunk.startsWith('[ERROR]')) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chunk.replaceFirst('[ERROR] ', ''))),
        );
        return;
      }
      assistantMessage = assistantMessage.copyWith(text: assistantMessage.text + chunk);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          assistantMessage,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
  }
  Future<void> _retryAssistantAt(int index) async {
    if (_sending) {
      return;
    }
    final ConversationMessage target = _conversation.messages[index];
    if (target.role != 'assistant') {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中完成 API 与模型配置。')),
      );
      return;
    }
    final List<ConversationMessage> contextMessages =
        _conversation.messages.take(index).toList();
    final List<Map<String, String>> payload = _buildMessagesFrom(contextMessages);
    setState(() => _sending = true);
    List<String> results = await _generateRetries(payload, model, apiKey, baseUrl);
    if (results.isEmpty) {
      results = await _generateRetriesSequential(payload, model, apiKey, baseUrl);
    }
    if (results.isEmpty) {
      _retryDisabled.add(target.id);
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重说失败，已暂时禁用。')),
        );
      }
      return;
    }
    _retryAlternatives.putIfAbsent(target.id, () => <String>[]);
    _retryAlternatives[target.id]!.addAll(results);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    await _showRetryPicker(index);
  }
  Future<List<String>> _generateRetries(
    List<Map<String, String>> payload,
    String model,
    String apiKey,
    String baseUrl,
  ) async {
    try {
      final List<Future<String?>> tasks = List<Future<String?>>.generate(3, (_) async {
        final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
        );
        if (!result.success || result.content == null) {
          return null;
        }
        return result.content!;
      });
      final List<String?> settled = await Future.wait(tasks);
      return settled.whereType<String>().where((String s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }
  Future<List<String>> _generateRetriesSequential(
    List<Map<String, String>> payload,
    String model,
    String apiKey,
    String baseUrl,
  ) async {
    final List<String> results = <String>[];
    for (int i = 0; i < 3; i++) {
      try {
        final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
        );
        if (result.success && result.content != null && result.content!.trim().isNotEmpty) {
          results.add(result.content!);
        }
      } catch (_) {
        // Ignore.
      }
    }
    return results;
  }
  Future<void> _showRetryPicker(int index) async {
    final ConversationMessage target = _conversation.messages[index];
    final List<String> options = _retryAlternatives[target.id] ?? <String>[];
    if (options.isEmpty) {
      return;
    }
    final String? selected = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        int? selectedIndex;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            return AlertDialog(
              title: const Text('重说结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int i) {
                    return RadioListTile<int>(
                      value: i,
                      groupValue: selectedIndex,
                      onChanged: (int? value) => setDialogState(() => selectedIndex = value),
                      title: Text(options[i]),
                    );
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('retry'),
                  child: const Text('再试三次'),
                ),
                FilledButton(
                  onPressed: selectedIndex == null
                      ? null
                      : () => Navigator.of(context).pop(options[selectedIndex!]),
                  child: const Text('使用此回复'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null) {
      return;
    }
    if (selected == 'retry') {
      await _retryAssistantAt(index);
      return;
    }
    final ConversationMessage updated = target.copyWith(text: selected);
    final List<ConversationMessage> updatedList = <ConversationMessage>[
      ..._conversation.messages.sublist(0, index),
      updated,
      ..._conversation.messages.sublist(index + 1),
    ];
    _conversation = _conversation.copyWith(messages: updatedList);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<void> _editAssistantAt(int index) async {
    final ConversationMessage target = _conversation.messages[index];
    final TextEditingController controller = TextEditingController(text: target.text);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('更改文字'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '输入新的内容'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (updated == null) {
      return;
    }
    final ConversationMessage updatedMessage = target.copyWith(text: updated);
    final List<ConversationMessage> updatedList = <ConversationMessage>[
      ..._conversation.messages.sublist(0, index),
      updatedMessage,
      ..._conversation.messages.sublist(index + 1),
    ];
    _conversation = _conversation.copyWith(messages: updatedList);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<void> _rollbackTo(int index) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认回溯'),
          content: const Text('将丢弃此气泡之后的所有记录，确定要回溯吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('回溯'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final List<ConversationMessage> trimmed = _conversation.messages.take(index + 1).toList();
    _conversation = _conversation.copyWith(messages: trimmed);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<void> _toggleBackground() async {
    final String next = _conversation.backgroundMode == 'image' ? 'none' : 'image';
    _conversation = _conversation.copyWith(backgroundMode: next);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final Role? role = _role;
    final Color schemeColor = _accent ?? Theme.of(context).colorScheme.primary;
    final Color userBubble = schemeColor.withValues(alpha: 0.18);
    final Color assistantBubble = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Size size = MediaQuery.of(context).size;
    final bool useLandscape = size.width >= size.height;
    final String? bgPath = useLandscape ? role?.images['landscape'] : role?.images['portrait'];
    final bool useImageBg = _conversation.backgroundMode == 'image' && bgPath != null && bgPath.isNotEmpty;
    final String searchQuery = _searchController.text.trim();
    final List<int> searchMatches =
        _searching && searchQuery.isNotEmpty ? _computeSearchMatches(searchQuery) : <int>[];
    final bool hasMatches = searchMatches.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '搜索消息',
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: _updateSearch,
                    ),
                  ),
                  Text(
                    hasMatches && _searchMatchIndex >= 0
                        ? '${_searchMatchIndex + 1}/${searchMatches.length}'
                        : '0/0',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              )
            : Text(role?.name.isNotEmpty == true ? role!.name : '聊天'),
        actions: _searching
            ? <Widget>[
                IconButton(
                  tooltip: '上一个',
                  onPressed: hasMatches ? () => _navigateMatch(-1) : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: '下一个',
                  onPressed: hasMatches ? () => _navigateMatch(1) : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: _toggleSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : <Widget>[
                IconButton(
                  tooltip: '回到底部',
                  onPressed: _scrollToBottom,
                  icon: const Icon(Icons.vertical_align_bottom),
                ),
                IconButton(
                  tooltip: _conversation.backgroundMode == 'image' ? '关闭背景图' : '显示背景图',
                  onPressed: _toggleBackground,
                  icon: Icon(_conversation.backgroundMode == 'image' ? Icons.image_not_supported : Icons.image),
                ),
              ],
      ),
      body: Stack(
        children: <Widget>[
          if (useImageBg)
            Positioned.fill(
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
              ),
            ),
          if (useImageBg)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
              ),
            ),
          Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _conversation.messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ConversationMessage message = _conversation.messages[index];
                    final bool isUser = message.role == 'user';
                    final Alignment alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
                    final Color bubbleColor = isUser ? userBubble : assistantBubble;
                    final GlobalKey key =
                        _messageKeys.putIfAbsent(message.id, () => GlobalKey(debugLabel: message.id));
                    final int charCount = message.text.runes.length;
                    final int tokenCount =
                        _showTokenCounts ? _countTokens(message.id, message.text) : 0;
                    return Align(
                      key: key,
                      alignment: alignment,
                      child: GestureDetector(
                        onLongPressStart: (LongPressStartDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            text: message.text,
                            isAssistant: !isUser,
                            index: index,
                          );
                        },
                        onSecondaryTapDown: (TapDownDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            text: message.text,
                            isAssistant: !isUser,
                            index: index,
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              RichText(text: _buildHighlightedText(context, message.text)),
                              if (message.text.isNotEmpty && _showTokenCounts) ...<Widget>[
                                const SizedBox(height: 6),
                                Text(
                                  '字数 $charCount / Token $tokenCount',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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
                      child: const Text('对方正在输入...'),
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(hintText: '输入消息...'),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: '更多',
                        onSelected: (String value) async {
                          if (value == 'archive') {
                            await _manageSnapshots();
                          } else if (value == 'search') {
                            _toggleSearch();
                          } else if (value == 'tokens') {
                            setState(() => _showTokenCounts = !_showTokenCounts);
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          CheckedPopupMenuItem<String>(
                            value: 'search',
                            checked: _searching,
                            child: const ListTile(
                              leading: Icon(Icons.search),
                              title: Text('消息搜索'),
                            ),
                          ),
                          CheckedPopupMenuItem<String>(
                            value: 'tokens',
                            checked: _showTokenCounts,
                            child: const ListTile(
                              leading: Icon(Icons.numbers),
                              title: Text('显示字数/Token'),
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'archive',
                            child: ListTile(
                              leading: Icon(Icons.save),
                              title: Text('存档'),
                            ),
                          ),
                        ],
                        child: const Icon(Icons.more_horiz),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        child: Text(_sending ? '发送中...' : '发送'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TokenCacheEntry {
  const _TokenCacheEntry({required this.text, required this.count});

  final String text;
  final int count;
}
class _ChatSnapshot {
  const _ChatSnapshot({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.data,
  });
  final String id;
  final String name;
  final int timestamp;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'timestamp': timestamp,
      'data': data,
    };
  }
  static _ChatSnapshot fromJson(Map<String, dynamic> json) {
    return _ChatSnapshot(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      timestamp: (json['timestamp'] as int?) ?? 0,
      data: (json['data'] as Map?)?.map((Object? k, Object? v) => MapEntry('$k', v)) ??
          <String, dynamic>{},
    );
  }
}
