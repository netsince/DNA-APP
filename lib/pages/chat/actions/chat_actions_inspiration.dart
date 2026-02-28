part of '../../chat_page.dart';

mixin ChatActionsInspiration on ChatStateMixin {
  List<Map<String, String>> _buildInspirationPayload(String topic);

  Future<void> _startInspiration() async {
    if (_inspirationInProgress) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (!ensureApiReady(context: context, controller: widget.controller)) {
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
      showSnack(context, '生成失败，请再试。');
      return;
    }
    _inspirationOptions.addAll(options);
    await _showInspirationDialog(model: model, apiKey: apiKey, baseUrl: baseUrl);
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
    return showTextInputDialog(
      context: context,
      title: '生成灵感',
      hintText: '生成灵感：例如 重新开场/ 继续推进 / 某个话题',
      confirmText: '生成',
    );
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
