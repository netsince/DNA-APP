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
    // 本次弹框内「再试」新追加的条数，用于给新结果打「新」标记
    int newlyAddedCount = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, StateSetter setSheet) {
            final ThemeData theme = Theme.of(sheetContext);
            final ColorScheme cs = theme.colorScheme;
            final Size screen = MediaQuery.of(sheetContext).size;

            Future<void> retry() async {
              setSheet(() => loading = true);
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
                newlyAddedCount = next.length;
              } else {
                showSnack(sheetContext, '生成失败，请再试。');
              }
              setSheet(() => loading = false);
            }

            final List<String> options = _inspirationOptions;
            final int firstNewIndex = options.length - newlyAddedCount;

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screen.height * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.lightbulb, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('灵感列表', style: theme.textTheme.titleLarge),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '主题：${_inspirationPrompt}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (loading) const LinearProgressIndicator(),
                  Flexible(
                    child: options.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                '暂无灵感，请点「再试」。',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            children: <Widget>[
                              for (int i = 0; i < options.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: RetryOptionCard(
                                    index: i,
                                    text: options[i],
                                    isNew: newlyAddedCount > 0 && i >= firstNewIndex,
                                    selected: selectedIndex == i,
                                    onTap: () => setSheet(() => selectedIndex = i),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      16 + MediaQuery.of(sheetContext).viewPadding.bottom,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: loading
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            child: const Text('关闭'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: loading ? null : retry,
                            icon: loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.autorenew),
                            label: Text(loading ? '生成中…' : '再试'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: selectedIndex == null
                                ? null
                                : () {
                                    final String picked = _inspirationOptions[selectedIndex!];
                                    _inputController.text = picked;
                                    _inputController.selection = TextSelection.fromPosition(
                                      TextPosition(offset: picked.length),
                                    );
                                    Navigator.of(sheetContext).pop();
                                  },
                            child: const Text('使用'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
