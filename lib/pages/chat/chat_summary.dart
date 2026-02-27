part of '../chat_page.dart';

mixin ChatSummaryHelpers on ChatStateMixin {
  bool _hasSummaryPrompt();
  int _totalTurnCount();
  String? _lastChatMessageId();
  List<ConversationMessage> _recentTurnSlice(int turnCount);
  String _buildPersonaWorldContext();
  void _insertMessageAfter(String anchorId, ConversationMessage message);
  void _removeMessageById(String messageId);

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

  Future<void> _dismissSummaryPrompt(String promptId) async {
    _removeMessageById(promptId);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
}
