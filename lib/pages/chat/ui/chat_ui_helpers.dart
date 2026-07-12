part of '../../chat_page.dart';

mixin ChatUiHelpers on ChatStateMixin {
  Future<void> _showSummaryDetail(String summaryId);
  Future<void> _editSummary(String summaryId);
  Future<void> _deleteSummary(String summaryId, String messageId);
  Future<void> _startSummaryFromPrompt(ConversationMessage message);
  void _dismissSummaryPrompt(String messageId);
  Future<void> _continueFromContext();
  Future<void> _retryAssistantAt(int index);
  Future<List<String>> _generateRetryCandidates(int index);
  @override
  Set<String> get _visibleThoughtMessageIds;

  Future<void> _showMessageMenu({
    required Offset position,
    required ConversationMessage message,
    required int index,
  }) async {
    // 若键盘展开或输入框仍持有焦点，长按仅收起焦点（同时收起键盘），不打开菜单；
    // 必须焦点完全离开输入框，再次长按才弹出菜单，避免菜单因输入框焦点而重新弹键盘
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bool inputFocused = _inputFocusNode.hasFocus;
    if (keyboardOpen || inputFocused) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final RelativeRect anchor = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );
    if (message.kind == 'summary') {
      final String? action = await showMenu<String>(
        context: context,
        position: anchor,
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'view_summary',
            child: ListTile(
              leading: Icon(Icons.article_outlined),
              title: Text('查看摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'edit_summary',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete_summary',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('删除摘要'),
            ),
          ),
        ],
      );
      if (action == null) {
        _scrollAfterMenu();
        return;
      }
      if (action == 'view_summary') {
        await _showSummaryDetail(message.summaryId ?? '');
      } else if (action == 'edit_summary') {
        await _editSummary(message.summaryId ?? '');
      } else if (action == 'delete_summary') {
        await _deleteSummary(message.summaryId ?? '', message.id);
      }
      _scrollAfterMenu();
      return;
    }
    if (message.kind == 'summary_prompt') {
      final String? action = await showMenu<String>(
        context: context,
        position: anchor,
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'start_summary',
            child: ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('生成摘要'),
            ),
          ),
          PopupMenuItem<String>(
            value: 'dismiss_summary',
            child: ListTile(
              leading: Icon(Icons.close),
              title: Text('忽略提示'),
            ),
          ),
        ],
      );
      if (action == null) {
        _scrollAfterMenu();
        return;
      }
      if (action == 'start_summary') {
        await _startSummaryFromPrompt(message);
      } else if (action == 'dismiss_summary') {
        _dismissSummaryPrompt(message.id);
      }
      _scrollAfterMenu();
      return;
    }
    final bool isAssistant = message.role == 'assistant';
    final bool retryDisabled = _retryDisabled.contains(_conversation.messages[index].id);
    final int lastAssistantIndex = _conversation.messages.lastIndexWhere(
      (ConversationMessage m) => m.kind == 'message' && m.role == 'assistant',
    );
    final bool canContinue = isAssistant && index == lastAssistantIndex;
    final bool hasThought = _thoughtsByMessageId.containsKey(message.id) &&
        _thoughtsByMessageId[message.id]!.text.trim().isNotEmpty;
    final bool isThoughtVisible = _visibleThoughtMessageIds.contains(message.id);
    final String? action = await showMenu<String>(
      context: context,
      position: anchor,
      items: <PopupMenuEntry<String>>[
        if (isAssistant)
          PopupMenuItem<String>(
            value: 'continue',
            enabled: canContinue,
            child: ListTile(
              leading: Icon(Icons.play_arrow),
              title: Text('继续说'),
            ),
          ),
        if (isAssistant)
          PopupMenuItem<String>(
            value: 'retry',
            enabled: canContinue && !retryDisabled,
            child: const ListTile(
              leading: Icon(Icons.refresh),
              title: Text('重说'),
            ),
          ),
        if (isAssistant)
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('更改文字'),
            ),
          ),
        if (isAssistant)
          const PopupMenuItem<String>(
            value: 'rollback',
            child: ListTile(
              leading: Icon(Icons.undo),
              title: Text('回溯到此处'),
            ),
          ),
        if (hasThought)
          PopupMenuItem<String>(
            value: isThoughtVisible ? 'hide_thought' : 'show_thought',
            child: ListTile(
              leading: Icon(isThoughtVisible ? Icons.psychology : Icons.psychology_outlined),
              title: Text(isThoughtVisible ? '隐藏思考' : '查看思考'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy),
            title: Text('复制'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'share',
          child: ListTile(
            leading: Icon(Icons.share),
            title: Text('分享'),
          ),
        ),
      ],
    );
    _scrollAfterMenu();
    if (action == null) {
      return;
    }
    if (action == 'continue') {
      await _continueFromContext();
      return;
    }
    if (action == 'retry') {
      await _retryAssistantAt(index);
      return;
    }
    if (action == 'edit') {
      await _editAssistantAt(index);
      return;
    }
    if (action == 'rollback') {
      await _rollbackTo(index);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (!mounted) {
        return;
      }
      showSnack(context, '已复制到剪贴板');
      return;
    }
    if (action == 'share') {
      await Share.share(message.text);
      return;
    }
    if (action == 'show_thought') {
      setState(() {
        _visibleThoughtMessageIds.add(message.id);
      });
      return;
    }
    if (action == 'hide_thought') {
      setState(() {
        _visibleThoughtMessageIds.remove(message.id);
      });
      return;
    }
  }

  Future<void> _showRetryPicker(int index) async {
    final ConversationMessage target = _conversation.messages[index];
    if (!(_retryAlternatives[target.id]?.isNotEmpty ?? false)) {
      return;
    }
    final String originalText = target.text;

    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        bool loading = false;
        // 当前选中的候选下标：先选中高亮，再点底部「使用」才生效，避免误触直接改回复
        int? selectedIndex;
        // 记录本次弹框内通过「再试」新追加的候选数量，用于给新结果打「新」标记
        int newlyAddedCount = 0;
        return StatefulBuilder(
          builder: (BuildContext sheetContext, StateSetter setSheet) {
            final ThemeData theme = Theme.of(sheetContext);
            final ColorScheme cs = theme.colorScheme;
            final Size screen = MediaQuery.of(sheetContext).size;
            final List<String> options =
                _retryAlternatives[target.id] ?? <String>[];

            Future<void> regenerate() async {
              setSheet(() => loading = true);
              final List<String> next = await _generateRetryCandidates(index);
              if (!mounted) {
                return;
              }
              if (next.isNotEmpty) {
                _retryAlternatives.putIfAbsent(target.id, () => <String>[]);
                _retryAlternatives[target.id]!.addAll(next);
                newlyAddedCount = next.length;
              } else {
                showSnack(sheetContext, '生成失败，请再试。');
              }
              setSheet(() => loading = false);
            }

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
                        Icon(Icons.refresh, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('重说结果', style: theme.textTheme.titleLarge),
                        const SizedBox(width: 8),
                        Text(
                          '共 ${options.length} 条',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (selectedIndex != null) const Spacer(),
                        if (selectedIndex != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '已选第 ${selectedIndex! + 1} 条',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (loading) const LinearProgressIndicator(),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: <Widget>[
                        _RetryOriginalCard(text: originalText),
                        const SizedBox(height: 12),
                        for (int i = 0; i < options.length; i++)
                          RetryOptionCard(
                            index: i,
                            text: options[i],
                            isNew: newlyAddedCount > 0 && i >= firstNewIndex,
                            selected: selectedIndex == i,
                            onTap: () => setSheet(() => selectedIndex = i),
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
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: loading ? null : regenerate,
                            icon: loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.autorenew),
                            label: Text(loading ? '生成中…' : '再生成三条'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: selectedIndex == null
                                ? null
                                : () => Navigator.of(sheetContext)
                                    .pop(options[selectedIndex!]),
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
    if (selected == null) {
      return;
    }
    final ConversationMessage updated = target.copyWith(text: selected);
    final List<ConversationMessage> updatedList = <ConversationMessage>[
      ..._conversation.messages.sublist(0, index),
      updated,
      ..._conversation.messages.sublist(index + 1),
    ];
    _conversation = _conversation.copyWith(messages: updatedList);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    // 重说完成后滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _editAssistantAt(int index) async {
    final ConversationMessage target = _conversation.messages[index];
    final TextEditingController controller = TextEditingController(text: target.text);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('更改文字'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '输入新的内容'),
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
    if (updated == null) {
      return;
    }
    final ConversationMessage updatedMessage = target.copyWith(text: updated);
    final List<ConversationMessage> updatedList = <ConversationMessage>[
      ..._conversation.messages.sublist(0, index),
      updatedMessage,
      ..._conversation.messages.sublist(index + 1),
    ];
    _conversation = _conversation.copyWith(messages: updatedList);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _rollbackTo(int index) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认回溯'),
          content: const Text('将丢弃此气泡之后的所有记录，确定要回溯吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('回溯'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final List<ConversationMessage> trimmed = _conversation.messages.take(index + 1).toList();
    final Set<String> remainingIds = trimmed.map((ConversationMessage m) => m.id).toSet();
    final List<ConversationSummary> summaries = _conversation.summaries
        .where((ConversationSummary s) => remainingIds.contains(s.endMessageId))
        .toList();
    _conversation = _conversation.copyWith(
      messages: trimmed,
      summaries: summaries,
    );
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
    // 回溯成功后滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollAfterMenu() {
    // 菜单关闭后，确保输入框不会因点击穿透或焦点残留而重新获得焦点、弹出键盘
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        _scrollToBottom();
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }
}

/// 「重说结果」弹框顶部展示的当前回复卡片，供用户与候选对照。
class _RetryOriginalCard extends StatelessWidget {
  const _RetryOriginalCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.chat_bubble_outline, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '当前回复',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text.trim().isEmpty ? '（空）' : text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 候选卡片：点击整卡即选中高亮，由底部「使用」确认生效。
/// 同时供「重说结果」与「灵感列表」复用，保证交互与视觉一致。
class RetryOptionCard extends StatelessWidget {
  const RetryOptionCard({
    required this.index,
    required this.text,
    required this.isNew,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool isNew;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: selected ? 2 : 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 13,
                  backgroundColor: selected ? cs.primary : cs.primaryContainer,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? cs.onPrimary : cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (isNew)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '新',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: selected ? cs.onPrimaryContainer : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.check_circle_outline,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
