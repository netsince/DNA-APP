import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';

import '../models/conversation.dart';
import '../models/dialogue_style.dart';
import '../models/role.dart';
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

  late Conversation _conversation;
  Color? _accent;
  bool _sending = false;

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
      id: DateTime.now().microsecondsSinceEpoch.toString(),
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
      id: DateTime.now().microsecondsSinceEpoch.toString(),
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
    final String assistantId = DateTime.now().microsecondsSinceEpoch.toString();
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

  List<Map<String, String>> _buildMessages() {
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
    final List<Map<String, String>> messages = <Map<String, String>>[];
    final String sys = system.toString().trim();
    if (sys.isNotEmpty) {
      messages.add(<String, String>{'role': 'system', 'content': sys});
    }
    for (final ConversationMessage message in _conversation.messages) {
      messages.add(<String, String>{
        'role': message.role,
        'content': message.text,
      });
    }
    return messages;
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

  Future<void> _showMessageMenu({
    required Offset position,
    required String text,
  }) async {
    final RelativeRect anchor = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );
    final String? action = await showMenu<String>(
      context: context,
      position: anchor,
      items: <PopupMenuEntry<String>>[
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

    return Scaffold(
      appBar: AppBar(
        title: Text(role?.name.isNotEmpty == true ? role!.name : '聊天'),
        actions: <Widget>[
          IconButton(
            tooltip: _conversation.backgroundMode == 'image' ? '关闭背景图' : '开启背景图',
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
                    return Align(
                      alignment: alignment,
                      child: GestureDetector(
                        onLongPressStart: (LongPressStartDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            text: message.text,
                          );
                        },
                        onSecondaryTapDown: (TapDownDetails details) {
                          _showMessageMenu(
                            position: details.globalPosition,
                            text: message.text,
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
                          child: Text(message.text),
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
