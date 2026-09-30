import 'package:flutter/material.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/pages/chat/chat_system_prompt.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/services/llm_request.dart';
import 'package:dna/services/llm_stream_chunk.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/utils/id_utils.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_bridge.dart';
import 'island_card.dart';
import 'trial_chat.dart';

/// 「试聊」：把一张角色卡**先聊两句**，再决定要不要收进「我家」。
///
/// * 默认走**设置里选定的模型** —— 与正式聊天同一个 provider、同一套采样
///   参数、同一份系统提示词，所以试聊的手感就是导入后的手感；
/// * 最多 [TrialChat.maxMessages] 条（用户 + 助手合计），满了必须二选一：
///   「导入角色卡接着聊」或「返回」；
/// * 记录**暂存本地**：中途退出再进来还在，但不会进「我家」的会话列表；
/// * 选「导入角色卡接着聊」时，这段记录会**原样带进新会话** —— 试聊不白聊。
///
/// **本地为主**：试聊不依赖岛服务器，只要有模型就能聊；只有「导入」那一步
/// 需要联网（去取卡片的导出包与立绘）。
class IslandTrialChatPage extends StatefulWidget {
  const IslandTrialChatPage({
    super.key,
    required this.controller,
    required this.card,
    this.api,
    this.completer,
  });

  final AppController controller;
  final IslandCard card;

  /// 导入时用的岛客户端；不传则内部自建。
  final IslandApi? api;

  /// 测试注入：把消息发给模型拿回复。默认走设置里的模型。
  final Future<String> Function(List<Map<String, String>> messages)? completer;

  @override
  State<IslandTrialChatPage> createState() => _IslandTrialChatPageState();
}

class _IslandTrialChatPageState extends State<IslandTrialChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ConversationMessage> _messages = <ConversationMessage>[];
  bool _loading = true;
  bool _sending = false;
  bool _busy = false;
  String? _error;

  bool get _isFull => _messages.length >= TrialChat.maxMessages;
  int get _remaining => TrialChat.maxMessages - _messages.length;

  /// 试聊用的 TA（只存在于内存，不落库）。
  late final TA _ta = widget.card.toTa(id: 'island-trial-${widget.card.id}');

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final TrialChat? saved = await TrialChatStore.load(widget.card.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = saved?.messages ?? _seedOpening();
      _loading = false;
    });
    if (saved == null) {
      await _persist();
    }
    _scrollToBottom();
  }

  /// 首次进入：把卡片的开场白作为第一条助手消息。
  List<ConversationMessage> _seedOpening() {
    final String opening = widget.card.opening.trim();
    if (opening.isEmpty) {
      return <ConversationMessage>[];
    }
    return <ConversationMessage>[
      ConversationMessage(
        id: newId(),
        role: 'assistant',
        text: opening,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
  }

  Future<void> _persist() =>
      TrialChatStore.save(TrialChat(card: widget.card, messages: _messages));

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 发给模型。默认走设置里选定的模型（与正式聊天同一条路）。
  Future<String> _ask(List<Map<String, String>> messages) async {
    final Future<String> Function(List<Map<String, String>>)? injected =
        widget.completer;
    if (injected != null) {
      return injected(messages);
    }
    final LlmRequest request = widget.controller.buildLlmRequest(
      messages: messages,
    );
    final StringBuffer buffer = StringBuffer();
    await for (final LlmStreamChunk chunk
        in widget.controller.llmProvider.streamChatCompletion(request)) {
      switch (chunk) {
        case LlmContentChunk(:final String text):
          buffer.write(text);
        case LlmErrorChunk(:final String message):
          throw IslandApiException(message);
        case LlmReasoningChunk():
        case LlmNoticeChunk():
          break;
      }
    }
    return buffer.toString();
  }

  List<Map<String, String>> _payload() => <Map<String, String>>[
    <String, String>{
      'role': 'system',
      'content': ChatSystemPrompt.build(ta: _ta, world: null),
    },
    for (final ConversationMessage m in _messages)
      <String, String>{
        'role': m.role == 'user' ? 'user' : 'assistant',
        'content': m.text,
      },
  ];

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending || _isFull) {
      return;
    }
    _input.clear();
    setState(() {
      _sending = true;
      _error = null;
      _messages = <ConversationMessage>[
        ..._messages,
        ConversationMessage(
          id: newId(),
          role: 'user',
          text: text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
    });
    await _persist();
    _scrollToBottom();

    try {
      final String reply = await _ask(_payload());
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <ConversationMessage>[
          ..._messages,
          ConversationMessage(
            id: newId(),
            role: 'assistant',
            text: reply.trim(),
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        ];
      });
      await _persist();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// 「导入角色卡接着聊」：导入 → 建会话（带上试聊记录）→ 进正式聊天页。
  Future<void> _importAndContinue() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final IslandApi api = widget.api ?? IslandApi();
    try {
      final TA ta = await IslandBridge.importCard(
        controller: widget.controller,
        api: api,
        card: widget.card,
      );
      final String conversationId = newId();
      await widget.controller.upsertConversation(
        Conversation(
          id: conversationId,
          taId: ta.id,
          worldId: null,
          note: '',
          // 试聊的记录原样带进新会话 —— 接着聊，不是从头开始。
          messages: _messages,
          backgroundMode: 'none',
          summaries: const <ConversationSummary>[],
          archived: false,
          isGroup: false,
          groupName: '',
          groupPrompt: '',
          memberTaIds: <String>[ta.id],
          activeTaId: ta.id,
        ),
      );
      await TrialChatStore.clear(widget.card.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ChatPage(
            controller: widget.controller,
            conversationId: conversationId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '导入失败：$e';
      });
    } finally {
      if (widget.api == null) {
        api.dispose();
      }
    }
  }

  /// 「返回」：丢弃这次试聊（满 10 条后必须明确二选一）。
  Future<void> _discardAndLeave() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const FitText('丢弃这次试聊？'),
        content: const FitText('试聊记录不会保留，也不会导入到「我家」。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const FitText('继续聊'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const FitText('丢弃'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    await TrialChatStore.clear(widget.card.id);
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: FitText(widget.card.name.trim().isEmpty ? '试聊' : widget.card.name),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: FitText(
                // 开场白算 1 条、每次发送 +2，总数是 1/3/5/7/9/11 —— 落不到
                // 整数 10，所以这里不写死数字，只说"还剩几句"与"聊满了"。
                _isFull ? '聊满了，请选择' : '还能聊 $_remaining 句',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isFull ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Expanded(child: _buildMessages(context)),
                if (_error != null) _buildError(context),
                _isFull
                    ? _buildForcedChoice(context)
                    : _buildInputBar(context),
              ],
            ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: FitText(
            '打个招呼试试？聊满 ${TrialChat.maxMessages} 句后可以导入「我家」接着聊。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _TrialBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: FitText(
        _error!,
        style: TextStyle(color: cs.onErrorContainer),
      ),
    );
  }

  /// 聊满之后的强制二选一。
  Widget _buildForcedChoice(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _busy ? null : _importAndContinue,
              icon: const Icon(Icons.download_outlined),
              label: FitText(_busy ? '正在导入…' : '导入角色卡接着聊'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _busy ? null : _discardAndLeave,
              child: const FitText('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_sending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '说点什么…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: '发送',
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// 试聊气泡。刻意做简单：这一页只负责"聊两句看看"，不做正式聊天那套。
class _TrialBubble extends StatelessWidget {
  const _TrialBubble({required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: FitText(
            message.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isUser ? cs.onPrimaryContainer : cs.onSurface,
              height: AppLineHeight.body,
            ),
          ),
        ),
      ),
    );
  }
}
