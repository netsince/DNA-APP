import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../models/conversation.dart';
import '../models/role.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import 'chat/chat_models.dart';
import 'chat/chat_snapshot_store.dart';
import 'chat/chat_stream_parser.dart';
import 'chat/chat_token_counter.dart';
import 'chat/chat_message_slice.dart';
import 'chat/chat_message_builder.dart';
import 'chat/chat_system_prompt.dart';
import 'chat/chat_state.dart';
import 'chat/chat_controller.dart';
import 'chat/widgets/chat_app_bar.dart';
import 'chat/widgets/chat_input_bar.dart';
import 'chat/widgets/chat_message_list.dart';

part 'chat/chat_state_mixin.dart';
part 'chat/chat_ui_helpers.dart';
part 'chat/chat_search.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.conversationId});
  final AppController controller;
  final String conversationId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}
class _ChatPageState extends State<ChatPage> with ChatStateMixin, ChatUiHelpers, ChatSearchHelpers {
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
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(_conversation);
    final ConversationSummary? summary = slice.includeSummary
        ? ChatMessageSlice.latestSummary(_conversation)
        : null;
    final List<Map<String, String>> payload = ChatMessageBuilder.buildMessagesFrom(
      systemPrompt: ChatSystemPrompt.build(role: _role, world: _world),
      messages: slice.messages,
      summaryText: summary?.text,
      summaryPrefix: '对话摘要：\n',
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
  String _buildSystemPrompt() {
    /*
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
    */
    return ChatSystemPrompt.build(role: _role, world: _world);
  }
  void _scrollToBottom() {
    _chatController.scrollToBottom();
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
    final ConversationSummary? summary = ChatMessageSlice.latestSummary(_conversation);
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
    final int summaryEnd = ChatMessageSlice.summaryEndIndex(_conversation);
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
    final ConversationSummary? previous = ChatMessageSlice.latestSummary(_conversation);
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
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      excludeIds: <String>{assistantId},
    );
    final List<Map<String, String>> payload = <Map<String, String>>[];
    final String sys = ChatSystemPrompt.build(role: _role, world: _world);
    if (sys.isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': sys});
    }
    if (slice.includeSummary) {
      final ConversationSummary? summary = ChatMessageSlice.latestSummary(_conversation);
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
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      endExclusive: index,
    );
    final ConversationSummary? summary = slice.includeSummary
        ? ChatMessageSlice.latestSummary(_conversation)
        : null;
    final List<Map<String, String>> payload = ChatMessageBuilder.buildMessagesFrom(
      systemPrompt: ChatSystemPrompt.build(role: _role, world: _world),
      messages: slice.messages,
      summaryText: summary?.text,
      summaryPrefix: '对话摘要：\n',
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
    return Scaffold(
      appBar: ChatAppBar(
        searching: _searching,
        searchController: _searchController,
        searchMatchIndex: _searchMatchIndex,
        searchMatchesCount: searchMatches.length,
        onSearchChanged: _updateSearch,
        onNavigateMatch: _navigateMatch,
        onToggleSearch: _toggleSearch,
        onScrollToBottom: _scrollToBottom,
        onToggleBackground: _toggleBackground,
        backgroundMode: _conversation.backgroundMode,
        role: role,
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
                child: ChatMessageList(
                  conversation: _conversation,
                  scrollController: _scrollController,
                  messageKeys: _messageKeys,
                  userBubble: userBubble,
                  assistantBubble: assistantBubble,
                  showTokenCounts: _showTokenCounts,
                  searchQuery: searchQuery,
                  thoughtsByMessageId: _thoughtsByMessageId,
                  tokenCountForMessage: (String messageId, String text) {
                    return _tokenCounter.countTokens(
                      model: widget.controller.settings.selectedModel,
                      messageId: messageId,
                      text: text,
                    );
                  },
                  summaryById: _summaryById,
                  onStartSummary: _startSummaryFromPrompt,
                  onDismissSummary: _dismissSummaryPrompt,
                  onShowMessageMenu: _showMessageMenu,
                  summaryInProgress: _summaryInProgress,
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
              ChatInputBar(
                inputController: _inputController,
                sending: _sending,
                inspirationInProgress: _inspirationInProgress,
                rangeSummaryInProgress: _rangeSummaryInProgress,
                summaryInProgress: _summaryInProgress,
                searching: _searching,
                showTokenCounts: _showTokenCounts,
                onSend: _send,
                onStartInspiration: _startInspiration,
                onManageSnapshots: _manageSnapshots,
                onToggleSearch: _toggleSearch,
                onToggleTokens: () => setState(() => _showTokenCounts = !_showTokenCounts),
                onForceSummary: _forceSummaryPrompt,
                onRangeSummary: _summarizeRecentRange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

