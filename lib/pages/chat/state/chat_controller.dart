import 'package:material_ui/material_ui.dart';

import '../../../models/conversation.dart';

class ChatController {
  ChatController({required this.scrollController});

  final ScrollController scrollController;

  /// 滚到列表底部。
  ///
  /// **内部已经排到下一帧**（`addPostFrameCallback`），调用方不要再包一层——
  /// 以前三处调用点各包了一遍，等于连排两帧才滚，表现为「发完消息先顿一下再滚」。
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
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
      if (conversation.messages[i].kindEnum == MessageKind.message &&
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
