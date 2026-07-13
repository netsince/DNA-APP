part of '../chat_page.dart';

mixin ChatSummaryHelpers on ChatStateMixin {
  bool _hasSummaryPrompt();
  int _totalTurnCount();
  String? _lastChatMessageId();
  List<ConversationMessage> _recentTurnSlice(int turnCount);
  String _buildPersonaWorldContext();
  void _insertMessageAfter(String anchorId, ConversationMessage message);
  void _removeMessageById(String messageId);

  // ignore: unused_element
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
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    final String? value = await showTextInputDialog(
      context: context,
      title: '范围总结',
      hintText: '用户轮数，例如 20',
      initialValue: '20',
      confirmText: '总结',
      keyboardType: TextInputType.number,
    );
    if (!mounted) {
      return;
    }
    if (value == null) {
      return;
    }
    final int? turnCount = int.tryParse(value);
    if (turnCount == null) {
      return;
    }
    final int normalized = turnCount.clamp(1, 200);
    final List<ConversationMessage> slice = _recentTurnSlice(normalized);
    if (slice.isEmpty) {
      showSnack(context, '没有可总结的内容。');
      return;
    }
    final StringBuffer convo = StringBuffer();
    for (final ConversationMessage m in slice) {
      final String roleLabel = m.role == 'user' ? '用户' : '助手';
      convo.writeln('$roleLabel: ${m.text}');
    }
    final String personaContext = _buildPersonaWorldContext();
    final World? world = _world;
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
      if (world != null && world.forbiddenWords.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content':
              '禁止输出词语：${world.forbiddenWords.join('、')}。即使历史对话或群设定中出现，也必须避免输出，可改写替换。',
        },
      <String, String>{
        'role': 'user',
        'content': '请总结最近 $normalized 轮用户对话：\n${convo.toString()}',
      },
    ];
    setState(() => _rangeSummaryInProgress = true);
    final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
      baseUrl: widget.controller.settings.baseUrl,
      apiKey: widget.controller.settings.apiKey,
      model: widget.controller.settings.selectedModel,
      messages: payload,
    );
    if (!mounted) {
      return;
    }
    setState(() => _rangeSummaryInProgress = false);
    if (!result.success || result.content == null) {
      showSnack(context, result.errorMessage ?? '总结失败。');
      return;
    }
    await showInfoDialog(
      context: context,
      title: '范围总结结果',
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Text(result.content!.trim()),
        ),
      ),
    );
  }

  Future<void> _startSummaryFromPrompt(ConversationMessage prompt) async {
    if (_summaryInProgress) {
      return;
    }
    if (!ensureApiReady(context: context, controller: widget.controller)) {
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
      showSnack(context, '没有可摘要的新内容。');
      return;
    }
    final List<ConversationMessage> sourceMessages = _conversation.messages
        .sublist(summaryEnd + 1, anchorIndex + 1)
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
    if (sourceMessages.isEmpty) {
      showSnack(context, '没有可摘要的新内容。');
      return;
    }
    final String sourceText = sourceMessages
        .map((ConversationMessage m) => '${m.role == 'user' ? '用户' : '助手'}：${m.text}')
        .join('\n');
    final ConversationSummary? previous = ChatMessageSlice.latestSummary(_conversation);
    final String personaContext = _buildPersonaWorldContext();
    final World? world = _world;
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
      if (world != null && world.forbiddenWords.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content':
              '禁止输出词语：${world.forbiddenWords.join('、')}。即使历史对话或群设定中出现，也必须避免输出，可改写替换。',
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
      baseUrl: widget.controller.settings.baseUrl,
      apiKey: widget.controller.settings.apiKey,
      model: widget.controller.settings.selectedModel,
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
        showSnack(context, result.errorMessage ?? '摘要失败。');
      }
      return;
    }

    final String summaryText = result.content!.trim();
    if (summaryText.isEmpty || summaryText.length >= sourceText.length) {
      if (mounted) {
        setState(() {});
        showSnack(context, '摘要过长，已自动舍弃。');
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
    showSnack(context, '已停止本次摘要。');
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
