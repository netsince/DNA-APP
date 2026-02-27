import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../models/conversation.dart';
import '../models/dialogue_style.dart';
import '../models/role.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import 'chat/chat_models.dart';
import 'chat/chat_snapshot_store.dart';
import 'chat/chat_stream_parser.dart';
import 'chat/chat_token_counter.dart';

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
  final ChatTokenCounter _tokenCounter = ChatTokenCounter();
  final ChatSnapshotStore _snapshotStore = ChatSnapshotStore();
  bool _summaryInProgress = false;
  int _summaryTaskId = 0;
  int? _cancelledSummaryTaskId;
  PendingSummary? _pendingSummary;
  bool _rangeSummaryInProgress = false;
  bool _inspirationInProgress = false;
  String _inspirationPrompt = '';
  final List<String> _inspirationOptions = <String>[];
  final Map<String, ThoughtEntry> _thoughtsByMessageId = <String, ThoughtEntry>{};
  final Map<String, StreamParseState> _streamParseStates = <String, StreamParseState>{};
  final Map<String, List<String>> _retryAlternatives = <String, List<String>>{};
  final Set<String> _retryDisabled = <String>{};
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
          summaries: const <ConversationSummary>[],
          archived: false,
        );
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
      final StreamParseState state = consumeStreamChunk(
        streamStates: _streamParseStates,
        thoughtsByMessageId: _thoughtsByMessageId,
        messageId: assistantId,
        chunk: chunk,
      );
      assistantMessage = assistantMessage.copyWith(text: state.visible);
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
    final String trimmed = assistantMessage.text.trim();
    if (trimmed != assistantMessage.text) {
      assistantMessage = assistantMessage.copyWith(text: trimmed);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          assistantMessage,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
    }
    setState(() => _sending = false);
    await _maybePromptSummary();
  }
  String _buildSystemPrompt() {
    final Role? role = _role;
    final World? world = _world;
    final List<DialogueTurn> style = role?.dialogueStyle ?? <DialogueTurn>[];
    final StringBuffer system = StringBuffer();
    system.writeln('你是“角色扮演对话”模式。必须严格遵守以下规则：');
    system.writeln('1) 括号“（…）”为旁白，只用于动作、表情、内心或环境描写，且尽量简短。');
    system.writeln('2) 每次回复只写一句话，不换行、不分段，不使用多句并列。');
    system.writeln('3) “*…*”仅用于音效/环境声/拟声。');
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
  ConversationSummary? _latestSummary() {
    if (_conversation.summaries.isEmpty) {
      return null;
    }
    return _conversation.summaries.last;
  }

  int _summaryEndIndex() {
    final ConversationSummary? summary = _latestSummary();
    if (summary == null || summary.endMessageId.isEmpty) {
      return -1;
    }
    return _conversation.messages.indexWhere((ConversationMessage m) => m.id == summary.endMessageId);
  }

  MessageSlice _sliceForPayload({
    int? endExclusive,
    Set<String>? excludeIds,
  }) {
    final int summaryEnd = _summaryEndIndex();
    final int total = _conversation.messages.length;
    final int end = endExclusive == null ? total : endExclusive.clamp(0, total);
    final bool includeSummary = summaryEnd >= 0 && end > summaryEnd;
    final int start = includeSummary ? summaryEnd + 1 : 0;
    final List<ConversationMessage> slice = _conversation.messages
        .sublist(start, end)
        .where((ConversationMessage m) => m.kind == 'message')
        .where((ConversationMessage m) => excludeIds == null || !excludeIds.contains(m.id))
        .toList();
    return MessageSlice(messages: slice, includeSummary: includeSummary);
  }

  List<Map<String, String>> _buildMessagesFrom(
    List<ConversationMessage> messages, {
    String? extraUserText,
    bool includeSummary = true,
  }) {
    final List<Map<String, String>> payload = <Map<String, String>>[];
    final String sys = _buildSystemPrompt();
    if (sys.isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': sys});
    }
    if (includeSummary) {
      final ConversationSummary? summary = _latestSummary();
      if (summary != null && summary.text.trim().isNotEmpty) {
        payload.add(<String, String>{
          'role': 'system',
          'content': '对话摘要：\n${summary.text.trim()}',
        });
      }
    }
    for (final ConversationMessage message in messages) {
      if (message.kind != 'message') {
        continue;
      }
      final String content = stripThoughtTags(message.text);
      payload.add(<String, String>{
        'role': message.role,
        'content': content,
      });
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }
  List<Map<String, String>> _buildMessages() {
    final MessageSlice slice = _sliceForPayload();
    return _buildMessagesFrom(
      slice.messages,
      includeSummary: slice.includeSummary,
    );
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
      if (_conversation.messages[i].kind == 'message' && text.toLowerCase().contains(lowerQuery)) {
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

  int _totalTurnCount() {
    int count = 0;
    for (final ConversationMessage message in _conversation.messages) {
      if (message.kind == 'message' && message.role == 'user') {
        count++;
      }
    }
    return count;
  }

  String? _lastChatMessageId() {
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind == 'message') {
        return message.id;
      }
    }
    return null;
  }

  ConversationSummary? _summaryById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final ConversationSummary summary in _conversation.summaries) {
      if (summary.id == id) {
        return summary;
      }
    }
    return null;
  }

  bool _hasSummaryPrompt() {
    return _conversation.messages.any((ConversationMessage m) => m.kind == 'summary_prompt');
  }

  List<ConversationMessage> _recentTurnSlice(int turnCount) {
    if (turnCount <= 0) {
      return <ConversationMessage>[];
    }
    int userTurns = 0;
    int startIndex = 0;
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind != 'message') {
        continue;
      }
      if (message.role == 'user') {
        userTurns++;
        if (userTurns == turnCount) {
          startIndex = i;
          break;
        }
      }
    }
    return _conversation.messages
        .sublist(startIndex)
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
  }

  String _buildPersonaWorldContext() {
    final Role? role = _role;
    final World? world = _world;
    final StringBuffer buffer = StringBuffer();
    if (role != null) {
      if (role.persona.trim().isNotEmpty) {
        buffer.writeln('Persona: ${role.persona.trim()}');
      }
      if (role.intro.trim().isNotEmpty) {
        buffer.writeln('Intro: ${role.intro.trim()}');
      }
    }
    if (world != null) {
      if (world.summary.trim().isNotEmpty) {
        buffer.writeln('World: ${world.summary.trim()}');
      } else if (world.description.trim().isNotEmpty) {
        buffer.writeln('World: ${world.description.trim()}');
      }
    }
    return buffer.toString().trim();
  }

  List<ConversationMessage> _latestMessages(int maxCount) {
    if (maxCount <= 0) {
      return <ConversationMessage>[];
    }
    final List<ConversationMessage> messages = _conversation.messages
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
    if (messages.length <= maxCount) {
      return messages;
    }
    return messages.sublist(messages.length - maxCount);
  }

  List<Map<String, String>> _buildInspirationPayload(String topic) {
    final String context = _buildPersonaWorldContext();
    final ConversationSummary? summary = _latestSummary();
    final bool includeSummary = widget.controller.settings.inspirationIncludeSummary &&
        summary != null &&
        summary.text.trim().isNotEmpty;
    final List<ConversationMessage> recent = _latestMessages(40);
    final List<String> recentUser = <String>[];
    final List<String> recentAssistant = <String>[];
    for (int i = recent.length - 1; i >= 0; i--) {
      final ConversationMessage m = recent[i];
      if (m.kind != 'message') {
        continue;
      }
    final String cleaned = stripThoughtTags(m.text).trim();
      if (cleaned.isEmpty) {
        continue;
      }
      if (m.role == 'user') {
        if (recentUser.length < 8) {
          recentUser.add(cleaned);
        }
      } else if (m.role == 'assistant') {
        if (recentAssistant.length < 4) {
          recentAssistant.add(cleaned);
        }
      }
      if (recentUser.length >= 8 && recentAssistant.length >= 4) {
        break;
      }
    }
    final List<String> recentUserOrdered = recentUser.reversed.toList();
    final List<String> recentAssistantOrdered = recentAssistant.reversed.toList();
    final List<Map<String, String>> payload = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': '你是灵感生成助手。你生成的是“用户要说的话”的灵感草稿，不是角色台词。必须使用用户视角、用户语气。不得模仿角色口吻，不得替角色发言。角色与世界观仅用于理解背景。只输出一句话的灵感建议，不要编号，不要解释。',
      },
      if (context.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '背景设定（仅供理解背景，不得模仿语气）：\n$context',
        },
      if (includeSummary)
        <String, String>{
          'role': 'system',
          'content': '最近摘要：\n${summary!.text.trim()}',
        },
      if (recentUserOrdered.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '用户最近发言（只用于内容衔接，保持用户视角与语气）：\n${recentUserOrdered.map((String s) => '- $s').join('\n')}',
        },
      if (recentAssistantOrdered.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '角色最近发言（仅供背景，不得模仿语气或措辞）：\n${recentAssistantOrdered.map((String s) => '- $s').join('\n')}',
        },
    ];
    final String safeTopic = topic.trim().isEmpty ? '继续对话' : topic.trim();
    payload.add(<String, String>{'role': 'user', 'content': '用户灵感：$safeTopic'});
    return payload;
  }

  Future<List<String>> _generateInspirations(
    List<Map<String, String>> payload, {
    required int count,
    required String model,
    required String apiKey,
    required String baseUrl,
  }) async {
    if (count <= 0) {
      return <String>[];
    }
    if (widget.controller.settings.retrySequential) {
      final List<String> results = <String>[];
      for (int i = 0; i < count; i++) {
        try {
          final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: payload,
          );
          if (result.success && result.content != null) {
            final String cleaned = stripThoughtTags(result.content!).trim();
            if (cleaned.isNotEmpty) {
              results.add(cleaned);
            }
          }
        } catch (_) {
          // Ignore.
        }
      }
      return results;
    }

    try {
      final List<Future<String?>> tasks = List<Future<String?>>.generate(count, (_) async {
        final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
        );
        if (!result.success || result.content == null) {
          return null;
        }
        return stripThoughtTags(result.content!).trim();
      });
      final List<String?> settled = await Future.wait(tasks);
      return settled.whereType<String>().where((String s) => s.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<String?> _promptInspirationTopic() async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('生成灵感'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '生成灵感：例如 重新开场 / 继续推进 / 某个话题'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('生成'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null) {
      return null;
    }
    return value.trim();
  }

  Future<void> _showInspirationDialog({
    required String model,
    required String apiKey,
    required String baseUrl,
  }) async {
    int? selectedIndex;
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            Future<void> retry() async {
              setDialogState(() => loading = true);
              final List<Map<String, String>> payload = _buildInspirationPayload(_inspirationPrompt);
              final List<String> next = await _generateInspirations(
                payload,
                count: 3,
                model: model,
                apiKey: apiKey,
                baseUrl: baseUrl,
              );
              if (next.isNotEmpty) {
                _inspirationOptions.addAll(next);
              }
              setDialogState(() => loading = false);
            }

            return AlertDialog(
              title: const Text('灵感列表'),
              content: SizedBox(
                width: double.maxFinite,
                child: _inspirationOptions.isEmpty
                    ? const Text('暂无灵感，请再试。')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _inspirationOptions.length,
                        itemBuilder: (BuildContext context, int index) {
                          return RadioListTile<int>(
                            value: index,
                            groupValue: selectedIndex,
                            onChanged: (int? value) => setDialogState(() => selectedIndex = value),
                            title: Text(_inspirationOptions[index]),
                          );
                        },
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: loading ? null : retry,
                  child: const Text('再试'),
                ),
                FilledButton(
                  onPressed: selectedIndex == null
                      ? null
                      : () {
                          final String picked = _inspirationOptions[selectedIndex!];
                          _inputController.text = picked;
                          _inputController.selection = TextSelection.fromPosition(
                            TextPosition(offset: picked.length),
                          );
                          Navigator.of(context).pop();
                        },
                  child: const Text('使用'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startInspiration() async {
    if (_inspirationInProgress) {
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
    final String? topic = await _promptInspirationTopic();
    if (topic == null) {
      return;
    }
    _inspirationPrompt = topic;
    _inspirationOptions.clear();
    setState(() => _inspirationInProgress = true);
    final List<Map<String, String>> payload = _buildInspirationPayload(_inspirationPrompt);
    final List<String> options = await _generateInspirations(
      payload,
      count: 3,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );
    if (!mounted) {
      return;
    }
    setState(() => _inspirationInProgress = false);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成失败，请再试。')),
      );
      return;
    }
    _inspirationOptions.addAll(options);
    await _showInspirationDialog(model: model, apiKey: apiKey, baseUrl: baseUrl);
  }

  void _insertMessageAfter(String anchorId, ConversationMessage message) {
    final List<ConversationMessage> updated = <ConversationMessage>[..._conversation.messages];
    final int index = updated.indexWhere((ConversationMessage m) => m.id == anchorId);
    if (index == -1) {
      updated.add(message);
    } else {
      updated.insert(index + 1, message);
    }
    _conversation = _conversation.copyWith(messages: updated);
  }

  void _removeMessageById(String messageId) {
    _conversation = _conversation.copyWith(
      messages: _conversation.messages.where((ConversationMessage m) => m.id != messageId).toList(),
    );
  }

  Future<void> _maybePromptSummary() async {
    if (!widget.controller.settings.autoSummaryPrompt) {
      return;
    }
    if (_summaryInProgress || _hasSummaryPrompt()) {
      return;
    }
    final int threshold = widget.controller.settings.summaryTurnInterval;
    final int totalTurns = _totalTurnCount();
    if (threshold <= 0 || totalTurns == 0 || totalTurns % threshold != 0) {
      return;
    }
    final String? anchorId = _lastChatMessageId();
    if (anchorId == null) {
      return;
    }
    final ConversationMessage prompt = ConversationMessage(
      id: newId(),
      role: 'system',
      text: '对话已达到摘要阈值，是否生成摘要？',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      kind: 'summary_prompt',
      anchorMessageId: anchorId,
    );
    _insertMessageAfter(anchorId, prompt);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }


  Future<void> _forceSummaryPrompt() async {
    if (_summaryInProgress) {
      return;
    }
    if (_hasSummaryPrompt()) {
      return;
    }
    final String? anchorId = _lastChatMessageId();
    if (anchorId == null) {
      return;
    }
    final ConversationMessage prompt = ConversationMessage(
      id: newId(),
      role: 'system',
      text: '已请求摘要，是否现在生成？',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      kind: 'summary_prompt',
      anchorMessageId: anchorId,
    );
    _insertMessageAfter(anchorId, prompt);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    await _startSummaryFromPrompt(prompt);
  }

  Future<void> _summarizeRecentRange() async {
    if (_rangeSummaryInProgress) {
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
    final TextEditingController controller = TextEditingController(text: '20');
    final int? turnCount = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('范围总结'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '用户轮数，例如 20',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                int.tryParse(controller.text.trim()),
              ),
              child: const Text('总结'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (turnCount == null) {
      return;
    }
    final int normalized = turnCount.clamp(1, 200);
    final List<ConversationMessage> slice = _recentTurnSlice(normalized);
    if (slice.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可总结的内容。')),
      );
      return;
    }
    final StringBuffer convo = StringBuffer();
    for (final ConversationMessage m in slice) {
      final String roleLabel = m.role == 'user' ? '用户' : '助手';
      convo.writeln('$roleLabel: ${m.text}');
    }
    final String personaContext = _buildPersonaWorldContext();
    final List<Map<String, String>> payload = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': '你是对话范围总结助手。请保留关键设定与事实，简洁总结最近对话，不要编造。',
      },
      if (personaContext.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '上下文：\n$personaContext',
        },
      <String, String>{
        'role': 'user',
        'content': '请总结最近 $normalized 轮用户对话：\n${convo.toString()}',
      },
    ];
    setState(() => _rangeSummaryInProgress = true);
    final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: payload,
    );
    if (!mounted) {
      return;
    }
    setState(() => _rangeSummaryInProgress = false);
    if (!result.success || result.content == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '总结失败。')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('范围总结结果'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(result.content!.trim()),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startSummaryFromPrompt(ConversationMessage prompt) async {
    if (_summaryInProgress) {
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
    final String? anchorId = prompt.anchorMessageId ?? _lastChatMessageId();
    if (anchorId == null) {
      return;
    }
    final int summaryEnd = _summaryEndIndex();
    final int anchorIndex =
        _conversation.messages.indexWhere((ConversationMessage m) => m.id == anchorId);
    if (anchorIndex == -1 || anchorIndex <= summaryEnd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可摘要的新内容。')),
      );
      return;
    }
    final List<ConversationMessage> sourceMessages = _conversation.messages
        .sublist(summaryEnd + 1, anchorIndex + 1)
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
    if (sourceMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可摘要的新内容。')),
      );
      return;
    }
    final String sourceText = sourceMessages
        .map((ConversationMessage m) => '${m.role == 'user' ? '用户' : '助手'}：${m.text}')
        .join('\n');
    final ConversationSummary? previous = _latestSummary();
    final String personaContext = _buildPersonaWorldContext();
    final List<Map<String, String>> payload = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': '你是对话摘要助手。请用简洁要点总结对话，保留关键设定、关系、计划与事实，不要编造。',
      },
      if (personaContext.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '上下文：\n$personaContext',
        },
      if (previous != null && previous.text.trim().isNotEmpty)
        <String, String>{'role': 'user', 'content': '已有摘要：\n${previous.text.trim()}'},
      <String, String>{'role': 'user', 'content': '新增对话：\n$sourceText'},
    ];

    _summaryInProgress = true;
    final int taskId = ++_summaryTaskId;
    _cancelledSummaryTaskId = null;
    _pendingSummary = PendingSummary(
      taskId: taskId,
      anchorMessageId: anchorId,
      sourceText: sourceText,
      promptMessageId: prompt.id,
    );
    if (mounted) {
      setState(() {});
    }

    final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: payload,
    );

    if (!mounted || _pendingSummary?.taskId != taskId || _cancelledSummaryTaskId == taskId) {
      return;
    }

    _summaryInProgress = false;
    _pendingSummary = null;

    if (!result.success || result.content == null) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? '摘要失败。')),
        );
      }
      return;
    }

    final String summaryText = result.content!.trim();
    if (summaryText.isEmpty || summaryText.length >= sourceText.length) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('摘要过长，已自动舍弃。')),
        );
      }
      return;
    }

    final ConversationSummary summary = ConversationSummary(
      id: newId(),
      text: summaryText,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      endMessageId: anchorId,
    );

    final ConversationMessage summaryBubble = ConversationMessage(
      id: newId(),
      role: 'system',
      text: '摘要已生成 · 长按查看/删除',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      kind: 'summary',
      summaryId: summary.id,
      anchorMessageId: anchorId,
    );

    _conversation = _conversation.copyWith(
      summaries: <ConversationSummary>[..._conversation.summaries, summary],
    );

    _removeMessageById(prompt.id);
    _insertMessageAfter(anchorId, summaryBubble);
    await widget.controller.upsertConversation(_conversation);

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _cancelSummary() {
    if (!_summaryInProgress || _pendingSummary == null) {
      return;
    }
    _cancelledSummaryTaskId = _pendingSummary!.taskId;
    _summaryInProgress = false;
    _pendingSummary = null;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已停止本次摘要。')),
    );
  }

  Future<void> _showSummaryDetail(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('对话摘要'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(summary.text),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSummary(String summaryId, String bubbleId) async {
    _conversation = _conversation.copyWith(
      summaries: _conversation.summaries.where((ConversationSummary s) => s.id != summaryId).toList(),
      messages: _conversation.messages.where((ConversationMessage m) => m.id != bubbleId).toList(),
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _editSummary(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    final TextEditingController controller = TextEditingController(text: summary.text);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('编辑摘要'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(hintText: '输入新的摘要内容'),
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
    controller.dispose();
    if (updated == null || updated.trim().isEmpty) {
      return;
    }
    final List<ConversationSummary> updatedSummaries = _conversation.summaries
        .map(
          (ConversationSummary s) => s.id == summaryId
              ? ConversationSummary(
                  id: s.id,
                  text: updated.trim(),
                  createdAt: s.createdAt,
                  endMessageId: s.endMessageId,
                )
              : s,
        )
        .toList();
    _conversation = _conversation.copyWith(summaries: updatedSummaries);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _dismissSummaryPrompt(String promptId) async {
    _removeMessageById(promptId);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<List<ChatSnapshot>> _loadSnapshots() async {
    return _snapshotStore.loadSnapshots(_conversation.id);
  }

  Future<void> _saveSnapshots(List<ChatSnapshot> snapshots) async {
    await _snapshotStore.saveSnapshots(_conversation.id, snapshots);
  }
  Future<void> _manageSnapshots() async {
    final List<ChatSnapshot> snapshots = await _loadSnapshots();
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
                      final ChatSnapshot snapshot = snapshots[index];
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
        ChatSnapshot(
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
    required ConversationMessage message,
    required int index,
  }) async {
    final RelativeRect anchor = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );
    if (message.kind == 'summary') {
      final String? action = await showMenu<String>(
        context: context,
        position: anchor,
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'view_summary',
            child: ListTile(
              leading: Icon(Icons.article_outlined),
              title: Text('查看摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'edit_summary',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete_summary',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('删除摘要'),
            ),
          ),
        ],
      );
      if (action == null) {
        return;
      }
      if (action == 'view_summary') {
        await _showSummaryDetail(message.summaryId ?? '');
      } else if (action == 'edit_summary') {
        await _editSummary(message.summaryId ?? '');
      } else if (action == 'delete_summary') {
        await _deleteSummary(message.summaryId ?? '', message.id);
      }
      return;
    }
    if (message.kind == 'summary_prompt') {
      final String? action = await showMenu<String>(
        context: context,
        position: anchor,
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'start_summary',
            child: ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('生成摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'dismiss_summary',
            child: ListTile(
              leading: Icon(Icons.close),
              title: Text('忽略提示'),
            ),
          ),
        ],
      );
      if (action == null) {
        return;
      }
      if (action == 'start_summary') {
        await _startSummaryFromPrompt(message);
      } else if (action == 'dismiss_summary') {
        _dismissSummaryPrompt(message.id);
      }
      return;
    }
    final bool isAssistant = message.role == 'assistant';
    final bool retryDisabled = _retryDisabled.contains(_conversation.messages[index].id);
    final int lastAssistantIndex = _conversation.messages.lastIndexWhere(
      (ConversationMessage m) => m.kind == 'message' && m.role == 'assistant',
    );
    final bool canContinue = isAssistant && index == lastAssistantIndex;
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
      await Clipboard.setData(ClipboardData(text: message.text));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
      return;
    }
    if (action == 'share') {
      await Share.share(message.text);
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
    final MessageSlice slice = _sliceForPayload(excludeIds: <String>{assistantId});
    final List<Map<String, String>> payload = <Map<String, String>>[];
    final String sys = _buildSystemPrompt();
    if (sys.isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': sys});
    }
    if (slice.includeSummary) {
      final ConversationSummary? summary = _latestSummary();
      if (summary != null && summary.text.trim().isNotEmpty) {
        payload.add(<String, String>{
          'role': 'system',
          'content': '对话摘要：\n${summary.text.trim()}',
        });
      }
    }
    payload.add(<String, String>{
      'role': 'system',
      'content': '请继续上一条助手回复，延续语气，不要重复已说内容，不要引入新话题。',
    });
    payload.addAll(
      slice.messages.map((ConversationMessage m) => <String, String>{
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
      final StreamParseState state = consumeStreamChunk(
        streamStates: _streamParseStates,
        thoughtsByMessageId: _thoughtsByMessageId,
        messageId: assistantId,
        chunk: chunk,
      );
      assistantMessage = assistantMessage.copyWith(text: state.visible);
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
    final String trimmed = assistantMessage.text.trim();
    if (trimmed != assistantMessage.text) {
      assistantMessage = assistantMessage.copyWith(text: trimmed);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          assistantMessage,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
    }
    setState(() => _sending = false);
    await _maybePromptSummary();
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
    final MessageSlice slice = _sliceForPayload(endExclusive: index);
    final List<Map<String, String>> payload = _buildMessagesFrom(
      slice.messages,
      includeSummary: slice.includeSummary,
    );
    setState(() => _sending = true);
    List<String> results = <String>[];
    if (widget.controller.settings.retrySequential) {
      results = await _generateRetriesSequential(payload, model, apiKey, baseUrl);
    } else {
      results = await _generateRetries(payload, model, apiKey, baseUrl);
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
    final Set<String> remainingIds = trimmed.map((ConversationMessage m) => m.id).toSet();
    final List<ConversationSummary> summaries = _conversation.summaries
        .where((ConversationSummary s) => remainingIds.contains(s.endMessageId))
        .toList();
    _conversation = _conversation.copyWith(
      messages: trimmed,
      summaries: summaries,
    );
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
                    final GlobalKey key =
                        _messageKeys.putIfAbsent(message.id, () => GlobalKey(debugLabel: message.id));
                    if (message.kind == 'summary_prompt') {
                      return Align(
                        key: key,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onLongPressStart: (LongPressStartDetails details) {
                            _showMessageMenu(
                              position: details.globalPosition,
                              message: message,
                              index: index,
                            );
                          },
                          onSecondaryTapDown: (TapDownDetails details) {
                            _showMessageMenu(
                              position: details.globalPosition,
                              message: message,
                              index: index,
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(Icons.auto_awesome, size: 18),
                                    const SizedBox(width: 6),
                                    const Text('建议生成摘要'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: <Widget>[
                                    FilledButton.tonal(
                                      onPressed: _summaryInProgress
                                          ? null
                                          : () => _startSummaryFromPrompt(message),
                                      child: const Text('生成摘要'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _dismissSummaryPrompt(message.id),
                                      child: const Text('忽略'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    if (message.kind == 'summary') {
                      final ConversationSummary? summary = _summaryById(message.summaryId);
                      final String raw = summary?.text.trim() ?? '';
                      final String preview = raw.isEmpty
                          ? '摘要为空'
                          : (raw.length > 80 ? '${raw.substring(0, 80)}...' : raw);
                      return Align(
                        key: key,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onLongPressStart: (LongPressStartDetails details) {
                            _showMessageMenu(
                              position: details.globalPosition,
                              message: message,
                              index: index,
                            );
                          },
                          onSecondaryTapDown: (TapDownDetails details) {
                            _showMessageMenu(
                              position: details.globalPosition,
                              message: message,
                              index: index,
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(Icons.article_outlined, size: 18),
                                    const SizedBox(width: 6),
                                    const Text('摘要已生成'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preview,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '长按/右键查看/删除',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    final bool isUser = message.role == 'user';
                    final Alignment alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
                    final Color bubbleColor = isUser ? userBubble : assistantBubble;
                    final int charCount = message.text.runes.length;
                    final int tokenCount = _showTokenCounts
                        ? _tokenCounter.countTokens(
                            model: widget.controller.settings.selectedModel,
                            messageId: message.id,
                            text: message.text,
                          )
                        : 0;
                    final String thoughtText =
                        _thoughtsByMessageId[message.id]?.text.trim() ?? '';
                    return Align(
                      key: key,
                      alignment: alignment,
                      child: GestureDetector(
                        onLongPressStart: (LongPressStartDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            message: message,
                            index: index,
                          );
                        },
                        onSecondaryTapDown: (TapDownDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            message: message,
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
                              if (thoughtText.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: const EdgeInsets.only(top: 6),
                                    title: const Text('思考内容'),
                                    children: <Widget>[
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          thoughtText,
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
              if (_summaryInProgress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.auto_awesome, size: 16),
                          const SizedBox(width: 6),
                          const Text('正在生成摘要...'),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _cancelSummary,
                            child: const Text('停止'),
                          ),
                        ],
                      ),
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
                      IconButton(
                        tooltip: '灵感',
                        onPressed: _inspirationInProgress ? null : _startInspiration,
                        icon: _inspirationInProgress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '更多',
                        onSelected: (String value) async {
                          if (value == 'archive') {
                            await _manageSnapshots();
                          } else if (value == 'search') {
                            _toggleSearch();
                          } else if (value == 'tokens') {
                            setState(() => _showTokenCounts = !_showTokenCounts);
                          } else if (value == 'force_summary') {
                            await _forceSummaryPrompt();
                          } else if (value == 'range_summary') {
                            await _summarizeRecentRange();
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'range_summary',
                            enabled: !_rangeSummaryInProgress,
                            child: ListTile(
                              leading: Icon(Icons.summarize_outlined),
                              title: Text('范围总结'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'force_summary',
                            enabled: !_summaryInProgress,
                            child: ListTile(
                              leading: Icon(Icons.auto_awesome),
                              title: Text('强制摘要'),
                            ),
                          ),
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

