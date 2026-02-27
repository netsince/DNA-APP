part of '../chat_page.dart';

mixin ChatStreamHandlers on ChatStateMixin {
  Future<bool> _streamAssistantResponse({
    required String model,
    required String apiKey,
    required String baseUrl,
    required List<Map<String, String>> payload,
    required String assistantId,
    required ConversationMessage assistantMessage,
  }) async {
    ConversationMessage message = assistantMessage;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chunk.replaceFirst('[ERROR] ', ''))),
        );
        return false;
      }
      final StreamParseState state = consumeStreamChunk(
        streamStates: _streamParseStates,
        thoughtsByMessageId: _thoughtsByMessageId,
        messageId: assistantId,
        chunk: chunk,
      );
      message = message.copyWith(text: state.visible);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          message,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return false;
      }
      setState(() {});
      _scrollToBottom();
    }

    if (!mounted) {
      return false;
    }
    final String trimmed = message.text.trim();
    if (trimmed != message.text) {
      message = message.copyWith(text: trimmed);
      _conversation = _conversation.copyWith(
        messages: <ConversationMessage>[
          ..._conversation.messages.where((ConversationMessage m) => m.id != assistantId),
          message,
        ],
      );
      await widget.controller.upsertConversation(_conversation);
    }
    return true;
  }
}
