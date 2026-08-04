part of '../../chat_page.dart';

mixin ChatActionsSend on ChatStateMixin {
  Future<bool> _streamAssistantResponse({
    required String model,
    required String apiKey,
    required String baseUrl,
    required List<Map<String, String>> payload,
    required String assistantId,
    required ConversationMessage assistantMessage,
  });
  Future<void> _maybePromptSummary();
  Future<void> _showRetryPicker(int index);

  Future<void> _setActiveTa(String taId) async {
    if (!_isGroup) {
      return;
    }
    if (_activeTaId == taId) {
      return;
    }
    final List<String> members = _memberTaIds.contains(taId)
        ? _memberTaIds
        : <String>[..._memberTaIds, taId];
    _conversation = _conversation.copyWith(
      memberTaIds: members,
      activeTaId: taId,
    );
    await widget.controller.upsertGroupConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    await _loadAccent();
  }

  TA? _taForMessage(ConversationMessage message) {
    final String? taId = message.speakerTaId;
    if (taId != null && taId.isNotEmpty) {
      return widget.controller.getTaById(taId);
    }
    return _ta;
  }

  /// 群聊历史身份标注：根据消息的 speakerTaId 解析说话者名字。
  String? _speakerNameFor(String? taId) {
    if (taId == null || taId.isEmpty) {
      return null;
    }
    return widget.controller.getTaById(taId)?.name;
  }

  /// 收集当前对话文本中命中的世界词条（Lorebook 动态激活）。
  List<WorldEntry> _activeLoreEntries(List<ConversationMessage> messages) {
    final World? world = _world;
    if (world == null || world.entries.isEmpty) {
      return <WorldEntry>[];
    }
    final StringBuffer sb = StringBuffer();
    for (final ConversationMessage m in messages) {
      if (m.kind != 'message') {
        continue;
      }
      final String t = stripThoughtTags(m.text).trim();
      if (t.isEmpty) {
        continue;
      }
      sb.write(t);
      sb.write(' ');
    }
    return WorldLorebook.match(world, sb.toString());
  }

  Future<void> _send() async {
    final String text = _inputController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    final TA? ta = _ta;
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    final ConversationMessage userMessage = ConversationMessage(
      id: newId(),
      role: 'user',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _inputController.clear();
    final List<ConversationMessage> updated = <ConversationMessage>[
      ..._conversation.messages,
      userMessage,
    ];
    _conversation = _conversation.copyWith(messages: updated);
    if (_isGroup) {
      await widget.controller.upsertGroupConversation(_conversation);
    } else {
      await widget.controller.upsertConversation(_conversation);
    }
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    if (_isGroup) {
      return;
    }
    if (ta == null) {
      showSnack(context, 'TA不存在，请重新创建会话。');
      return;
    }
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    setState(() => _sending = true);
    final String assistantId = newId();
    ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[..._conversation.messages, assistantMessage],
      activeTaId: ta.id,
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      maxMessages: widget.controller.settings.maxContextMessages,
      maxTokens: widget.controller.settings.maxContextTokens,
      tokenCounter: _tokenCounter,
      tokenModel: widget.controller.settings.selectedModel,
    );
    final ConversationSummary? summary =
        slice.includeSummary ? ChatMessageSlice.latestSummary(_conversation) : null;
    final List<Map<String, String>> payload = ChatMessageBuilder.buildMessagesFrom(
      systemPrompt: ChatSystemPrompt.build(
        ta: ta,
        world: _world,
        groupPrompt: _conversation.groupPrompt,
        strategy: widget.controller.settings.promptStrategy,
        identity: widget.controller.getIdentityById(_conversation.identityId),
        groupMembers: _isGroup ? _memberTas : null,
      ),
      messages: slice.messages,
      summaryText: summary?.text,
      summaryPrefix: '对话摘要：\n',
      prefixSpeaker: _isGroup,
      speakerNameResolver: _speakerNameFor,
      activeEntries: _activeLoreEntries(slice.messages),
      authorNote: widget.controller.settings.authorNote,
      authorNoteInterval: widget.controller.settings.authorNoteInterval,
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

  // ignore: unused_element
  Future<void> _continueFromContext() async {
    if (_sending) {
      return;
    }
    final int lastAssistantIndex = _conversation.messages.lastIndexWhere(
      (ConversationMessage m) => m.kind == 'message' && m.role == 'assistant',
    );
    if (lastAssistantIndex == -1) {
      return;
    }
    final TA? ta = _taForMessage(_conversation.messages[lastAssistantIndex]);
    if (ta == null) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    setState(() => _sending = true);
    final String assistantId = newId();
    ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[..._conversation.messages, assistantMessage],
      activeTaId: ta.id,
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
      maxMessages: widget.controller.settings.maxContextMessages,
      maxTokens: widget.controller.settings.maxContextTokens,
      tokenCounter: _tokenCounter,
      tokenModel: widget.controller.settings.selectedModel,
    );
    final List<Map<String, String>> payload = <Map<String, String>>[];
    final String sys = ChatSystemPrompt.build(
      ta: ta,
      world: _world,
      groupPrompt: _conversation.groupPrompt,
      strategy: widget.controller.settings.promptStrategy,
      identity: widget.controller.getIdentityById(_conversation.identityId),
      groupMembers: _isGroup ? _memberTas : null,
      activeEntries: _activeLoreEntries(slice.messages),
    );
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
            'content': ChatMessageBuilder.resolveContentWithSpeaker(
              message: m,
              prefixSpeaker: _isGroup,
              speakerNameResolver: _speakerNameFor,
            ),
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

  // ignore: unused_element
  Future<void> _retryAssistantAt(int index) async {
    if (_sending) {
      return;
    }
    final ConversationMessage target = _conversation.messages[index];
    if (target.role != 'assistant') {
      return;
    }
    if (_taForMessage(target) == null) {
      return;
    }
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    setState(() => _sending = true);
    final List<String> results = await _generateRetryCandidates(index);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (results.isEmpty) {
      _retryDisabled.add(target.id);
      showSnack(context, '重试失败，已暂时禁用。');
      return;
    }
    _retryAlternatives.putIfAbsent(target.id, () => <String>[]);
    _retryAlternatives[target.id]!.addAll(results);
    await _showRetryPicker(index);
  }

  /// 生成一批「重说」候选文本（默认 3 条），不涉及任何 UI。
  /// 供首次重说与弹框内「再试」内联复用。
  Future<List<String>> _generateRetryCandidates(int index) async {
    if (index < 0 || index >= _conversation.messages.length) {
      return <String>[];
    }
    final ConversationMessage target = _conversation.messages[index];
    if (target.role != 'assistant') {
      return <String>[];
    }
    final TA? ta = _taForMessage(target);
    if (ta == null) {
      return <String>[];
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      endExclusive: index,
      maxMessages: widget.controller.settings.maxContextMessages,
      maxTokens: widget.controller.settings.maxContextTokens,
      tokenCounter: _tokenCounter,
      tokenModel: widget.controller.settings.selectedModel,
    );
    final ConversationSummary? summary =
        slice.includeSummary ? ChatMessageSlice.latestSummary(_conversation) : null;
    final List<Map<String, String>> payload = ChatMessageBuilder.buildMessagesFrom(
      systemPrompt: ChatSystemPrompt.build(
        ta: ta,
        world: _world,
        groupPrompt: _conversation.groupPrompt,
        strategy: widget.controller.settings.promptStrategy,
        identity: widget.controller.getIdentityById(_conversation.identityId),
        groupMembers: _isGroup ? _memberTas : null,
      ),
      messages: slice.messages,
      summaryText: summary?.text,
      summaryPrefix: '对话摘要：\n',
      prefixSpeaker: _isGroup,
      speakerNameResolver: _speakerNameFor,
      activeEntries: _activeLoreEntries(slice.messages),
      authorNote: widget.controller.settings.authorNote,
      authorNoteInterval: widget.controller.settings.authorNoteInterval,
    );
    if (widget.controller.settings.retrySequential) {
      return _generateRetriesSequential(payload, model, apiKey, baseUrl);
    }
    return _generateRetries(payload, model, apiKey, baseUrl);
  }

  Future<List<String>> _generateRetries(
    List<Map<String, String>> payload,
    String model,
    String apiKey,
    String baseUrl,
  ) async {
    try {
      final List<Future<String?>> tasks = List<Future<String?>>.generate(3, (_) async {
        final ChatCompletionResult result = await widget.controller.llmProvider.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
          temperature: widget.controller.settings.temperature,
          frequencyPenalty: widget.controller.settings.frequencyPenalty,
          presencePenalty: widget.controller.settings.presencePenalty,
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
        final ChatCompletionResult result = await widget.controller.llmProvider.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
          temperature: widget.controller.settings.temperature,
          frequencyPenalty: widget.controller.settings.frequencyPenalty,
          presencePenalty: widget.controller.settings.presencePenalty,
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

  Future<void> _triggerTaReply(TA ta) async {
    if (_sending) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    await _setActiveTa(ta.id);
    setState(() => _sending = true);
    final String assistantId = newId();
    ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[..._conversation.messages, assistantMessage],
      activeTaId: ta.id,
    );
    await widget.controller.upsertGroupConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      excludeIds: <String>{assistantId},
      maxMessages: widget.controller.settings.maxContextMessages,
      maxTokens: widget.controller.settings.maxContextTokens,
      tokenCounter: _tokenCounter,
      tokenModel: widget.controller.settings.selectedModel,
    );
    final ConversationSummary? summary =
        slice.includeSummary ? ChatMessageSlice.latestSummary(_conversation) : null;
    final List<Map<String, String>> payload = ChatMessageBuilder.buildMessagesFrom(
      systemPrompt: ChatSystemPrompt.build(
        ta: ta,
        world: _world,
        groupPrompt: _conversation.groupPrompt,
        strategy: widget.controller.settings.promptStrategy,
        identity: widget.controller.getIdentityById(_conversation.identityId),
        groupMembers: _isGroup ? _memberTas : null,
      ),
      messages: slice.messages,
      summaryText: summary?.text,
      summaryPrefix: '对话摘要：\n',
      prefixSpeaker: _isGroup,
      speakerNameResolver: _speakerNameFor,
      activeEntries: _activeLoreEntries(slice.messages),
      authorNote: widget.controller.settings.authorNote,
      authorNoteInterval: widget.controller.settings.authorNoteInterval,
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
}
