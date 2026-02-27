part of '../chat_page.dart';

mixin ChatPayloadBuilders on ChatStateMixin {
  String _buildSystemPrompt() {
    return ChatSystemPrompt.build(role: _role, world: _world);
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

  Future<List<String>> _generateInspirations(
    List<Map<String, String>> payload, {
    required int count,
    required String model,
    required String apiKey,
    required String baseUrl,
  }) async {
    if (count <= 0) {
      return <String>[];
    }
    if (widget.controller.settings.retrySequential) {
      final List<String> results = <String>[];
      for (int i = 0; i < count; i++) {
        try {
          final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: payload,
          );
          if (result.success && result.content != null) {
            final String cleaned = stripThoughtTags(result.content!).trim();
            if (cleaned.isNotEmpty) {
              results.add(cleaned);
            }
          }
        } catch (_) {
          // Ignore.
        }
      }
      return results;
    }

    try {
      final List<Future<String?>> tasks = List<Future<String?>>.generate(count, (_) async {
        final ChatCompletionResult result = await widget.controller.openAiService.createChatCompletion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: payload,
        );
        if (!result.success || result.content == null) {
          return null;
        }
        return stripThoughtTags(result.content!).trim();
      });
      final List<String?> settled = await Future.wait(tasks);
      return settled.whereType<String>().where((String s) => s.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<String?> _promptInspirationTopic() async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('生成灵感'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '生成灵感：例如 重新开场 / 继续推进 / 某个话题'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('生成'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null) {
      return null;
    }
    return value.trim();
  }

  Future<void> _showInspirationDialog({
    required String model,
    required String apiKey,
    required String baseUrl,
  }) async {
    int? selectedIndex;
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            Future<void> retry() async {
              setDialogState(() => loading = true);
              final List<Map<String, String>> payload = _buildInspirationPayload(_inspirationPrompt);
              final List<String> next = await _generateInspirations(
                payload,
                count: 3,
                model: model,
                apiKey: apiKey,
                baseUrl: baseUrl,
              );
              if (next.isNotEmpty) {
                _inspirationOptions.addAll(next);
              }
              setDialogState(() => loading = false);
            }

            return AlertDialog(
              title: const Text('灵感列表'),
              content: SizedBox(
                width: double.maxFinite,
                child: _inspirationOptions.isEmpty
                    ? const Text('暂无灵感，请再试。')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _inspirationOptions.length,
                        itemBuilder: (BuildContext context, int index) {
                          return RadioListTile<int>(
                            value: index,
                            groupValue: selectedIndex,
                            onChanged: (int? value) => setDialogState(() => selectedIndex = value),
                            title: Text(_inspirationOptions[index]),
                          );
                        },
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: loading ? null : retry,
                  child: const Text('再试'),
                ),
                FilledButton(
                  onPressed: selectedIndex == null
                      ? null
                      : () {
                          final String picked = _inspirationOptions[selectedIndex!];
                          _inputController.text = picked;
                          _inputController.selection = TextSelection.fromPosition(
                            TextPosition(offset: picked.length),
                          );
                          Navigator.of(context).pop();
                        },
                  child: const Text('使用'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
