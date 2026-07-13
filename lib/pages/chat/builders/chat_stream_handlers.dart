part of '../../chat_page.dart';

mixin ChatStreamHandlers on ChatStateMixin {
  // ignore: unused_element
  Future<bool> _streamAssistantResponse({
    required String model,
    required String apiKey,
    required String baseUrl,
    required List<Map<String, String>> payload,
    required String assistantId,
    required ConversationMessage assistantMessage,
  }) async {
    ConversationMessage message = assistantMessage;
    DateTime lastUpdate = DateTime.now();
    String lastText = '';
    const Duration updateInterval = Duration(milliseconds: 100);

    await for (final String chunk in widget.controller.openAiService.streamChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: payload,
    )) {
      if (!mounted) {
        return false;
      }

      if (chunk.startsWith('[ERROR]')) {
        setState(() => _sending = false);
        showSnack(context, chunk.replaceFirst('[ERROR] ', ''));
        return false;
      }

      final StreamParseState state = consumeStreamChunk(
        streamStates: _streamParseStates,
        thoughtsByMessageId: _thoughtsByMessageId,
        messageId: assistantId,
        chunk: chunk,
      );

      message = message.copyWith(text: state.visible);

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

    if (!mounted) {
      return false;
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
}
