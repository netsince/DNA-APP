part of '../chat_surface.dart';

/// 「继续说」追加在请求最尾部的 system 指令。
///
/// 必须是 system 而不是 user：它是对模型的额外要求，不是用户发言；
/// 尾随位置也不能变（KV cache 的公共前缀依赖历史之后才出现动态内容）。
const String _kContinueInstruction = '请继续上一条助手回复，延续语气，不要重复已说内容，不要引入新话题。';

mixin ChatActionsSend on ChatStateMixin {
  Future<bool> _streamAssistantResponse({
    required List<Map<String, dynamic>> payload,
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

  /// 当前对话使用的作者注释：仅来自角色卡（TA）绑定。
  /// 全局不再提供作者注释，未设置则不注入。
  String? _effectiveAuthorNote(TA? ta) {
    if (ta != null && ta.authorNote != null && ta.authorNote!.trim().isNotEmpty) {
      return ta.authorNote;
    }
    return null;
  }

  int _effectiveAuthorNoteInterval(TA? ta) {
    if (ta != null && ta.authorNote != null && ta.authorNote!.trim().isNotEmpty) {
      return ta.authorNoteInterval;
    }
    return 0;
  }

  /// Lorebook 跨轮状态：记录词条 sticky / 冷却 / 延迟的剩余轮数。
  final LorebookState _loreState = LorebookState();

  /// 记录上一次溢出告警的时间，避免连续发送时反复弹提示。
  int _lastLoreOverflowNotifyAt = 0;

  /// 收集当前对话文本中命中的世界词条（Lorebook 动态激活）。
  /// 支持高级匹配（正则/全词/大小写/递归）、冷却/延迟、sticky 持续保留，以及预算裁剪。
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
    final settings = widget.controller.settings;
    final LoreMatchResult result = WorldLorebook.match(
      world,
      sb.toString(),
      state: _loreState,
      stickyRounds: settings.loreStickyRounds,
      maxEntries: settings.loreMaxEntries,
      maxTokens: settings.loreBudgetTokens,
      tokenCounter: (String desc) => desc.isEmpty
          ? 0
          : _tokenCounter.countTokens(
              model: settings.selectedModel,
              messageId: 'lore-budget',
              text: desc,
            ),
    );
    // 预算溢出告警：最多每 10 秒提示一次，避免刷屏。
    if (result.overflow) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastLoreOverflowNotifyAt > 10000) {
        _lastLoreOverflowNotifyAt = now;
        if (mounted) {
          showSnack(
            context,
            '世界知识超出预算，已自动裁剪部分词条（可在设置中调整条数/token 上限）',
          );
        }
      }
    }
    return result.entries;
  }

  /// 生成当前对话的 Lorebook 尾部 system 文本（空串表示无激活词条）。
  /// 缓存友好：词条作为独立 system 消息追加在历史之后，不污染前缀。
  String _loreTextFor(List<ConversationMessage> messages) {
    final List<WorldEntry> entries = _activeLoreEntries(messages);
    if (entries.isEmpty) {
      return '';
    }
    return WorldLorebook.format(world: _world, entries: entries);
  }

  /// 处理快速回复：把宏替换成实际值后填充输入框并发送。
  void _handleQuickReply(QuickReply qr) {
    if (_sending) {
      return;
    }
    final UserIdentity? identity =
        widget.controller.getIdentityById(_conversation.identityId);
    // 开启命令宏时展开占位符；关闭时保持原样发送。
    String resolved = qr.message;
    if (widget.controller.settings.enableCommandMacros) {
      resolved = expandCommandMacros(
        resolved,
        charName: _ta?.name ?? '',
        userName: identity?.name ?? '',
      );
    }
    _inputController.text = resolved;
    _inputController.selection =
        TextSelection.collapsed(offset: resolved.length);
    _send();
  }

  /// 把当前会话装配成一次 LLM 请求的 payload。
  ///
  /// 「发送 / 重说候选 / 群聊点名」三个入口原本各抄一遍这 35 行（连注释都一样），
  /// 只差切片边界：[endExclusive] 切到某条之前，[excludeIds] 排除刚插入的占位消息。
  /// 汇总到一处：摘要插入、视觉读图、群聊视角、作者注、lore 这些参数少传一个，
  /// 就是「某个入口的请求和别人不一样」，而这种不一致很难被测试发现。
  Future<List<Map<String, dynamic>>> _assembleRequestPayload({
    required TA ta,
    int? endExclusive,
    Set<String>? excludeIds,
    String? systemTail,
  }) async {
    final ConversationSummary? latestSummary =
        ChatMessageSlice.latestSummary(_conversation);
    final MessageSlice slice = ChatMessageSlice.sliceForPayload(
      _conversation,
      endExclusive: endExclusive,
      excludeIds: excludeIds,
      maxMessages: widget.controller.settings.maxContextMessages,
      maxTokens: widget.controller.settings.maxContextTokens,
      tokenCounter: _tokenCounter,
      tokenModel: widget.controller.settings.selectedModel,
      summaryText: latestSummary?.text,
    );
    final ConversationSummary? summary =
        slice.includeSummary ? latestSummary : null;
    // 图片数据只在模型确实支持视觉时才读：不支持时读盘、base64 编码、
    // 塞进请求体全是白费，还可能把请求撑大。
    final Map<String, String> imageDataUrls =
        resolveVisionSupport(widget.controller.activeModel)
            ? await AttachmentImageLoader.instance.collectFor(slice.messages)
            : const <String, String>{};
    return ChatMessageBuilder.buildMessagesFrom(
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
      summaryPrefix: ChatMessageBuilder.summarySystemPrefix,
      groupPerspective: _isGroup,
      perspectiveTaId: ta.id,
      speakerNameResolver: _speakerNameFor,
      authorNote: _effectiveAuthorNote(ta),
      authorNoteInterval: _effectiveAuthorNoteInterval(ta),
      loreText: _loreTextFor(slice.messages),
      imageDataUrls: imageDataUrls,
      extraSystemTail: systemTail,
    );
  }

  /// 发起一轮助手生成：插占位消息 → 落库 → 刷新 → 滚到底，返回占位 id 与消息。
  ///
  /// [group] **必须由调用方显式给**，不要用 `_isGroup` 猜：单聊走
  /// `upsertConversation`，群聊必须走 `upsertGroupConversation` —— 写错会让
  /// 群聊在会话列表里「消失」（这个坑注释里踩过一次）。
  Future<({String id, ConversationMessage message})> _beginAssistantTurn(
    TA ta, {
    required bool group,
  }) async {
    final String assistantId = newId();
    final ConversationMessage assistantMessage = ConversationMessage(
      id: assistantId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[
        ..._conversation.messages,
        assistantMessage,
      ],
      activeTaId: ta.id,
    );
    if (group) {
      await widget.controller.upsertGroupConversation(_conversation);
    } else {
      await widget.controller.upsertConversation(_conversation);
    }
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
    return (id: assistantId, message: assistantMessage);
  }

  /// 一轮助手生成的收尾：只有真的流过才复位 `_sending` 并尝试摘要提示。
  ///
  /// [streamed] 为 false 时什么都不做：`_streamAssistantResponse` 在失败分支里
  /// 已经自己把 `_sending` 复位了，这里再复位反而会掩盖错误路径。
  Future<void> _endAssistantTurn({required bool streamed}) async {
    if (!streamed) {
      return;
    }
    setState(() => _sending = false);
    await _maybePromptSummary();
  }

  Future<void> _send() async {
    String text = _inputController.text.trim();
    // 附件也能单独发：只带文件、不写字是合法输入。
    final List<MessageAttachment> pending =
        List<MessageAttachment>.of(_attachmentDraft.items);
    if ((text.isEmpty && pending.isEmpty) || _sending) {
      return;
    }
    // 模型吃不下图片就别发出去（入口已置灰，这里兜住手快的情况）。
    final bool vision = resolveVisionSupport(widget.controller.activeModel);
    if (!vision && pending.any((MessageAttachment a) => a.isImage)) {
      showSnack(context, '当前模型未开启图片支持，请在「模型设置」里打开，或先移除图片。');
      return;
    }
    // 发送前按「命令宏 + 正则替换」处理用户输入。
    final UserIdentity? identity =
        widget.controller.getIdentityById(_conversation.identityId);
    if (widget.controller.settings.enableCommandMacros) {
      text = expandCommandMacros(
        text,
        charName: _ta?.name ?? '',
        userName: identity?.name ?? '',
      );
    }
    if (widget.controller.settings.enableRegexReplacement) {
      text = applyRegexRules(
        text,
        widget.controller.settings.regexRules,
      ).trim();
    }
    if (text.isEmpty && pending.isEmpty) {
      return;
    }
    final TA? ta = _ta;
    final ConversationMessage userMessage = ConversationMessage(
      id: newId(),
      role: 'user',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      attachments: pending,
    );
    _inputController.clear();
    _attachmentDraft.clear();
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
    final ({String id, ConversationMessage message}) turn =
        await _beginAssistantTurn(ta, group: false);
    if (!mounted) {
      return;
    }
    final List<Map<String, dynamic>> payload =
        await _assembleRequestPayload(ta: ta);
    final bool streamed = await _streamAssistantResponse(
      payload: payload,
      assistantId: turn.id,
      assistantMessage: turn.message,
    );
    await _endAssistantTurn(streamed: streamed);
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
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    setState(() => _sending = true);
    final ({String id, ConversationMessage message}) turn =
        await _beginAssistantTurn(ta, group: false);
    if (!mounted) {
      return;
    }
    // 与「发送 / 重说候选」走同一个装配入口：摘要前缀、视觉读图、群聊视角、
    // 作者注、lore 一律由它负责；唯一多出来的是一条**尾随 system 指令**。
    final List<Map<String, dynamic>> payload = await _assembleRequestPayload(
      ta: ta,
      excludeIds: <String>{turn.id},
      systemTail: _kContinueInstruction,
    );
    final bool streamed = await _streamAssistantResponse(
      payload: payload,
      assistantId: turn.id,
      assistantMessage: turn.message,
    );
    await _endAssistantTurn(streamed: streamed);
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
    final List<Map<String, dynamic>> payload =
        await _assembleRequestPayload(ta: ta, endExclusive: index);
    // 群聊输出防线:剥掉模型自带「自己名字：」前缀(全/半角冒号),
    // 避免候选文本入库后与历史前缀叠成「名字：名字：」。
    final List<String> candidates = widget.controller.settings.retrySequential
        ? await _generateRetriesSequential(payload)
        : await _generateRetries(payload);
    return candidates
        .map((String c) => ChatMessageBuilder.stripOwnSpeakerPrefix(c, ta.name))
        .where((String c) => c.trim().isNotEmpty)
        .toList();
  }

  /// 并发生成一批「重说」候选(默认 3 条),不涉及任何 UI。
  /// 请求间加入错峰延迟,降低同时并发触发限流的概率。
  Future<List<String>> _generateRetries(
    List<Map<String, dynamic>> payload,
  ) async {
    try {
      final List<Future<String?>> tasks =
          List<Future<String?>>.generate(3, (int i) async {
        if (i > 0) {
          await Future<void>.delayed(Duration(milliseconds: 300 * i));
        }
        final ChatCompletionResult result =
            await widget.controller.llmProvider.createChatCompletion(
          widget.controller.buildLlmRequest(messages: payload),
        );
        if (!result.success || result.content == null) {
          return null;
        }
        return result.content!;
      });
      final List<String?> settled = await Future.wait(tasks);
      return settled
          .whereType<String>()
          .where((String s) => s.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<List<String>> _generateRetriesSequential(
    List<Map<String, dynamic>> payload,
  ) async {
    final List<String> results = <String>[];
    for (int i = 0; i < 3; i++) {
      try {
        final ChatCompletionResult result =
            await widget.controller.llmProvider.createChatCompletion(
          widget.controller.buildLlmRequest(messages: payload),
        );
        if (result.success &&
            result.content != null &&
            result.content!.trim().isNotEmpty) {
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
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    await _setActiveTa(ta.id);
    setState(() => _sending = true);
    final ({String id, ConversationMessage message}) turn =
        await _beginAssistantTurn(ta, group: true);
    if (!mounted) {
      return;
    }
    final List<Map<String, dynamic>> payload =
        await _assembleRequestPayload(ta: ta, excludeIds: <String>{turn.id});
    final bool streamed = await _streamAssistantResponse(
      payload: payload,
      assistantId: turn.id,
      assistantMessage: turn.message,
    );
    await _endAssistantTurn(streamed: streamed);
  }
}
