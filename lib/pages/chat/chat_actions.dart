part of '../chat_page.dart';

mixin ChatActions on ChatStateMixin {
  Future<bool> _streamAssistantResponse({
    required String model,
    required String apiKey,
    required String baseUrl,
    required List<Map<String, String>> payload,
    required String assistantId,
    required ConversationMessage assistantMessage,
  });
  Future<void> _maybePromptSummary();
  List<Map<String, String>> _buildInspirationPayload(String topic);
  ConversationSummary? _summaryById(String? summaryId);
  Future<void> _showRetryPicker(int index);
  void _scrollToBottom();
  Future<void> _startInspiration() async {
    if (_inspirationInProgress) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (model.isEmpty || apiKey.isEmpty || baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中完成 API 与模型配置。')),
      );
      return;
    }
    final String? topic = await _promptInspirationTopic();
    if (topic == null) {
      return;
    }
    _inspirationPrompt = topic;
    _inspirationOptions.clear();
    setState(() => _inspirationInProgress = true);
    final List<Map<String, String>> payload = _buildInspirationPayload(_inspirationPrompt);
    final List<String> options = await _generateInspirations(
      payload,
      count: 3,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
    );
    if (!mounted) {
      return;
    }
    setState(() => _inspirationInProgress = false);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成失败，请再试。')),
      );
      return;
    }
    _inspirationOptions.addAll(options);
    await _showInspirationDialog(model: model, apiKey: apiKey, baseUrl: baseUrl);
  }

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

  void _removeMessageById(String messageId) {
    _conversation = _conversation.copyWith(
      messages: _conversation.messages.where((ConversationMessage m) => m.id != messageId).toList(),
    );
  }

  Future<void> _showSummaryDetail(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('对话摘要'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(summary.text),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSummary(String summaryId, String bubbleId) async {
    _conversation = _conversation.copyWith(
      summaries: _conversation.summaries.where((ConversationSummary s) => s.id != summaryId).toList(),
      messages: _conversation.messages.where((ConversationMessage m) => m.id != bubbleId).toList(),
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _editSummary(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    final TextEditingController controller = TextEditingController(text: summary.text);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('编辑摘要'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(hintText: '输入新的摘要内容'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (updated == null || updated.trim().isEmpty) {
      return;
    }
    final List<ConversationSummary> updatedSummaries = _conversation.summaries
        .map(
          (ConversationSummary s) => s.id == summaryId
              ? ConversationSummary(
                  id: s.id,
                  text: updated.trim(),
                  createdAt: s.createdAt,
                  endMessageId: s.endMessageId,
                )
              : s,
        )
        .toList();
    _conversation = _conversation.copyWith(summaries: updatedSummaries);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<List<ChatSnapshot>> _loadSnapshots() async {
    return _snapshotStore.loadSnapshots(_conversation.id);
  }

  Future<void> _saveSnapshots(List<ChatSnapshot> snapshots) async {
    await _snapshotStore.saveSnapshots(_conversation.id, snapshots);
  }
  Future<void> _manageSnapshots() async {
    final List<ChatSnapshot> snapshots = await _loadSnapshots();
    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('存档管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: snapshots.isEmpty
                ? const Text('暂无存档')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshots.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatSnapshot snapshot = snapshots[index];
                      final DateTime time = DateTime.fromMillisecondsSinceEpoch(snapshot.timestamp);
                      return ListTile(
                        title: Text(snapshot.name),
                        subtitle: Text(time.toString().substring(0, 19)),
                        onTap: () => Navigator.of(context).pop('load:$index'),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('create'),
              child: const Text('新建存档'),
            ),
          ],
        );
      },
    );
    if (action == null) {
      return;
    }
    if (action == 'create') {
      final String defaultName = '存档 ${DateTime.now().toString().substring(0, 19)}';
      final TextEditingController controller = TextEditingController(text: defaultName);
      final String? name = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('创建存档'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入存档名称'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      snapshots.insert(
        0,
        ChatSnapshot(
          id: newId(),
          name: name.trim(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          data: _conversation.toJson(),
        ),
      );
      await _saveSnapshots(snapshots);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('存档已保存。')),
      );
      return;
    }
    if (action.startsWith('load:')) {
      final int index = int.tryParse(action.split(':').last) ?? -1;
      if (index < 0 || index >= snapshots.length) {
        return;
      }
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('确认加载存档'),
            content: const Text('将覆盖当前对话并无法撤销，确定要继续吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshots[index].data);
      data['id'] = _conversation.id;
      _conversation = Conversation.fromJson(data);
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
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
