part of '../../chat_page.dart';

mixin ChatPayloadBuilders on ChatStateMixin {
  String _buildSystemPrompt() {
    return ChatSystemPrompt.build(
      role: _role,
      world: _world,
      groupPrompt: _conversation.groupPrompt,
    );
  }

  int _totalTurnCount() {
    int count = 0;
    for (final ConversationMessage message in _conversation.messages) {
      if (message.kind == 'message' && message.role == 'user') {
        count++;
      }
    }
    return count;
  }

  String? _lastChatMessageId() {
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind == 'message') {
        return message.id;
      }
    }
    return null;
  }

  ConversationSummary? _summaryById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final ConversationSummary summary in _conversation.summaries) {
      if (summary.id == id) {
        return summary;
      }
    }
    return null;
  }

  bool _hasSummaryPrompt() {
    return _conversation.messages.any((ConversationMessage m) => m.kind == 'summary_prompt');
  }

  List<ConversationMessage> _recentTurnSlice(int turnCount) {
    if (turnCount <= 0) {
      return <ConversationMessage>[];
    }
    int userTurns = 0;
    int startIndex = 0;
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind != 'message') {
        continue;
      }
      if (message.role == 'user') {
        userTurns++;
        if (userTurns == turnCount) {
          startIndex = i;
          break;
        }
      }
    }
    return _conversation.messages
        .sublist(startIndex)
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
  }

  String _buildPersonaWorldContext() {
    final Role? role = _role;
    final World? world = _world;
    final StringBuffer buffer = StringBuffer();
    if (role != null) {
      if (role.persona.trim().isNotEmpty) {
        buffer.writeln('Persona: ${role.persona.trim()}');
      }
      if (role.intro.trim().isNotEmpty) {
        buffer.writeln('Intro: ${role.intro.trim()}');
      }
    }
    if (world != null) {
      if (world.summary.trim().isNotEmpty) {
        buffer.writeln('World: ${world.summary.trim()}');
      } else if (world.description.trim().isNotEmpty) {
        buffer.writeln('World: ${world.description.trim()}');
      }
    }
    return buffer.toString().trim();
  }

  List<ConversationMessage> _latestMessages(int maxCount) {
    if (maxCount <= 0) {
      return <ConversationMessage>[];
    }
    final List<ConversationMessage> messages = _conversation.messages
        .where((ConversationMessage m) => m.kind == 'message')
        .toList();
    if (messages.length <= maxCount) {
      return messages;
    }
    return messages.sublist(messages.length - maxCount);
  }

  List<Map<String, String>> _buildInspirationPayload(String topic) {
    final String context = _buildPersonaWorldContext();
    final ConversationSummary? summary = ChatMessageSlice.latestSummary(_conversation);
    final bool includeSummary = widget.controller.settings.inspirationIncludeSummary &&
        summary != null &&
        summary.text.trim().isNotEmpty;
    final List<ConversationMessage> recent = _latestMessages(40);
    final List<String> recentUser = <String>[];
    final List<String> recentAssistant = <String>[];
    for (int i = recent.length - 1; i >= 0; i--) {
      final ConversationMessage m = recent[i];
      if (m.kind != 'message') {
        continue;
      }
    final String cleaned = stripThoughtTags(m.text).trim();
      if (cleaned.isEmpty) {
        continue;
      }
      if (m.role == 'user') {
        if (recentUser.length < 8) {
          recentUser.add(cleaned);
        }
      } else if (m.role == 'assistant') {
        if (recentAssistant.length < 4) {
          recentAssistant.add(cleaned);
        }
      }
      if (recentUser.length >= 8 && recentAssistant.length >= 4) {
        break;
      }
    }
    final List<String> recentUserOrdered = recentUser.reversed.toList();
    final List<String> recentAssistantOrdered = recentAssistant.reversed.toList();
    final List<Map<String, String>> payload = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': '你是灵感生成助手。你生成的是“用户要说的话”的灵感草稿，不是角色台词。必须使用用户视角、用户语气。不得模仿角色口吻，不得替角色发言。角色与世界观仅用于理解背景。只输出一句话的灵感建议，不要编号，不要解释。',
      },
      if (context.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '背景设定（仅供理解背景，不得模仿语气）：\n$context',
        },
      if (includeSummary)
        <String, String>{
          'role': 'system',
          'content': '最近摘要：\n${summary!.text.trim()}',
        },
      if (recentUserOrdered.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '用户最近发言（只用于内容衔接，保持用户视角与语气）：\n${recentUserOrdered.map((String s) => '- $s').join('\n')}',
        },
      if (recentAssistantOrdered.isNotEmpty)
        <String, String>{
          'role': 'system',
          'content': '角色最近发言（仅供背景，不得模仿语气或措辞）：\n${recentAssistantOrdered.map((String s) => '- $s').join('\n')}',
        },
    ];
    final String safeTopic = topic.trim().isEmpty ? '继续对话' : topic.trim();
    payload.add(<String, String>{'role': 'user', 'content': '用户灵感：$safeTopic'});
    return payload;
  }

}
