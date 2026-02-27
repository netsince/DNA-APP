import 'package:flutter/material.dart';

import '../../models/conversation.dart';

class ChatController {
  ChatController({required this.scrollController});

  final ScrollController scrollController;

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      scrollController.animateTo(
        scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  List<int> computeSearchMatches(Conversation conversation, String query) {
    if (query.isEmpty) {
      return <int>[];
    }
    final String lowerQuery = query.toLowerCase();
    final List<int> matches = <int>[];
    for (int i = 0; i < conversation.messages.length; i++) {
      final String text = conversation.messages[i].text;
      if (conversation.messages[i].kind == 'message' &&
          text.toLowerCase().contains(lowerQuery)) {
        matches.add(i);
      }
    }
    return matches;
  }

  void jumpToMessageIndex({
    required Conversation conversation,
    required Map<String, GlobalKey> messageKeys,
    required int messageIndex,
  }) {
    if (messageIndex < 0 || messageIndex >= conversation.messages.length) {
      return;
    }
    final String id = conversation.messages[messageIndex].id;
    final GlobalKey? key = messageKeys[id];
    if (key == null || key.currentContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      key.currentContext!,
      alignment: 0.3,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
}
