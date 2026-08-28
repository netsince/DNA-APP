part of '../../chat_page.dart';

mixin ChatStreamHandlers on ChatStateMixin {
  // ignore: unused_element
  Future<bool> _streamAssistantResponse({
    required List<Map<String, String>> payload,
    required String assistantId,
    required ConversationMessage assistantMessage,
  }) async {
    ConversationMessage message = assistantMessage;
    DateTime lastUpdate = DateTime.now();
    String lastText = '';
    const Duration updateInterval = Duration(milliseconds: 100);
    _generationStopRequested = false;
    bool stoppedByUser = false;
    String? notice;

    // C2/C4:请求参数由控制器工厂从激活配置派生。
    final LlmRequest request = widget.controller.buildLlmRequest(messages: payload);

    await for (final LlmStreamChunk chunk
        in widget.controller.llmProvider.streamChatCompletion(request)) {
      if (!mounted) {
        // A4:用户已离开页面,把已生成的部分落库,避免只剩空气泡。
        await _persistPartialAssistantMessage(message, assistantId);
        return false;
      }

      if (_generationStopRequested) {
        // 停止生成:break 取消流订阅;基类在 generator finally 中关闭
        // 该流的独立连接,服务端生成随之中断(A3/A5)。
        stoppedByUser = true;
        break;
      }

      switch (chunk) {
        case LlmErrorChunk(:final message):
          setState(() => _sending = false);
          showSnack(context, message);
          return false;
        case LlmNoticeChunk(:final message):
          notice = notice == null ? message : '$notice\n$message';
          continue;
        case LlmReasoningChunk(:final text):
          // 思考通道直通:协议级 reasoning 不经标签状态机,
          // 直接累计到该消息的思考内容。
          final StreamParseState state =
              _streamParseStates.putIfAbsent(assistantId, () => StreamParseState());
          state.thought += text;
          _thoughtsByMessageId[assistantId] =
              ThoughtEntry(text: state.thought.trim());
          message = message.copyWith(text: state.visible);
        case LlmContentChunk(:final text):
          // 正文分片仍走标签状态机:模型可能在 content 里自带字面思考标签。
          final StreamParseState state = consumeStreamChunk(
            streamStates: _streamParseStates,
            thoughtsByMessageId: _thoughtsByMessageId,
            messageId: assistantId,
            chunk: text,
          );
          message = message.copyWith(text: state.visible);
      }

      final DateTime now = DateTime.now();
      final bool shouldUpdate = now.difference(lastUpdate) > updateInterval ||
          (message.text.length - lastText.length) > 50;

      if (shouldUpdate && mounted) {
        lastUpdate = now;
        lastText = message.text;

        _conversation = _conversation.copyWith(
          messages: <ConversationMessage>[
            ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
            message,
          ],
        );

        setState(() {});
        _scrollToBottom();
      }
    }
    _generationStopRequested = false;

    if (!mounted) {
      await _persistPartialAssistantMessage(message, assistantId);
      return false;
    }

    // 流结束(含手动停止):把 holdback 扣住的半截标签尾巴按字面文本归还。
    String finalText = finalizeStreamState(
      streamStates: _streamParseStates,
      thoughtsByMessageId: _thoughtsByMessageId,
      messageId: assistantId,
    );
    if (finalText.isEmpty && message.text.isNotEmpty) {
      finalText = message.text;
    }

    // 群聊输出防线:模型受历史「名字：台词」格式影响,输出可能自带名字前缀。
    // 入库/上屏前剥掉自己的那一层——既保证 UI 干净,也掐断下一轮
    // 「名字：名字：」滚雪球的源头(串角色问题的放大器)。
    final String? ownSpeakerName = _isGroup
        ? widget.controller.getTaById(message.speakerTaId ?? '')?.name
        : null;
    finalText = ChatMessageBuilder.stripOwnSpeakerPrefix(finalText, ownSpeakerName);
    message = message.copyWith(text: finalText);

    if (stoppedByUser) {
      setState(() => _sending = false);
      showSnack(context, '已停止生成');
    } else if (notice != null) {
      showSnack(context, notice);
    }

    final String trimmed = message.text.trim();
    if (trimmed != message.text) {
      message = message.copyWith(text: trimmed);
    }

    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[
        ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
        message,
      ],
    );

    await widget.controller.upsertConversation(_conversation);

    if (mounted) {
      setState(() {});
    }

    return true;
  }

  /// 把流式生成中已产出的部分内容持久化(页面退出/中断场景)。
  /// 内容为空时保持占位气泡原样,不产生多余写盘。
  Future<void> _persistPartialAssistantMessage(
    ConversationMessage partial,
    String assistantId,
  ) async {
    if (partial.text.trim().isEmpty) {
      return;
    }
    _conversation = _conversation.copyWith(
      messages: <ConversationMessage>[
        ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
        partial,
      ],
    );
    await widget.controller.upsertConversation(_conversation);
  }
}
