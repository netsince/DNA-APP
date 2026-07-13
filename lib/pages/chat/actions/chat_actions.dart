part of '../../chat_page.dart';

mixin ChatActions on ChatStateMixin {
  // ignore: unused_element
  void _insertMessageAfter(String anchorId, ConversationMessage message) {
    final List<ConversationMessage> updated = <ConversationMessage>[..._conversation.messages];
    final int index = updated.indexWhere((ConversationMessage m) => m.id == anchorId);
    if (index == -1) {
      updated.add(message);
    } else {
      updated.insert(index + 1, message);
    }
    _conversation = _conversation.copyWith(messages: updated);
  }

  // ignore: unused_element
  void _removeMessageById(String messageId) {
    _conversation = _conversation.copyWith(
      messages: _conversation.messages.where((ConversationMessage m) => m.id != messageId).toList(),
    );
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
}
