part of '../../chat_page.dart';

mixin ChatActionsSend on ChatStateMixin {
  Future<bool> _streamAssistantResponse({required String model, required String apiKey, required String baseUrl, required List<Map<String, String>> payload, required String assistantId, required ConversationMessage assistantMessage,});
  Future<void> _maybePromptSummary();
  Future<void> _showRetryPicker(int index);

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
    final bool streamed = await _streamAssistantResponse(
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      payload: payload,
      assistantId: assistantId,
      assistantMessage: assistantMessage,
    );
    if (!streamed) {
      return;
    }
    setState(() => _sending = false);
    await _maybePromptSummary();
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
    final bool streamed = await _streamAssistantResponse(
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      payload: payload,
      assistantId: assistantId,
      assistantMessage: assistantMessage,
    );
    if (!streamed) {
      return;
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
}
