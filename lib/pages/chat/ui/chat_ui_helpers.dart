part of '../../chat_page.dart';

mixin ChatUiHelpers on ChatStateMixin {
  Future<void> _showSummaryDetail(String summaryId);
  Future<void> _editSummary(String summaryId);
  Future<void> _deleteSummary(String summaryId, String messageId);
  Future<void> _startSummaryFromPrompt(ConversationMessage message);
  void _dismissSummaryPrompt(String messageId);
  Future<void> _continueFromContext();
  Future<void> _retryAssistantAt(int index);

  Future<void> _showMessageMenu({
    required Offset position,
    required ConversationMessage message,
    required int index,
  }) async {
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
        return;
      }
      if (action == 'view_summary') {
        await _showSummaryDetail(message.summaryId ?? '');
      } else if (action == 'edit_summary') {
        await _editSummary(message.summaryId ?? '');
      } else if (action == 'delete_summary') {
        await _deleteSummary(message.summaryId ?? '', message.id);
      }
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
        return;
      }
      if (action == 'start_summary') {
        await _startSummaryFromPrompt(message);
      } else if (action == 'dismiss_summary') {
        _dismissSummaryPrompt(message.id);
      }
      return;
    }
    final bool isAssistant = message.role == 'assistant';
    final bool retryDisabled = _retryDisabled.contains(_conversation.messages[index].id);
    final int lastAssistantIndex = _conversation.messages.lastIndexWhere(
      (ConversationMessage m) => m.kind == 'message' && m.role == 'assistant',
    );
    final bool canContinue = isAssistant && index == lastAssistantIndex;
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
            enabled: !retryDisabled,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
      return;
    }
    if (action == 'share') {
      await Share.share(message.text);
    }
  }

  Future<void> _showRetryPicker(int index) async {
    final ConversationMessage target = _conversation.messages[index];
    final List<String> options = _retryAlternatives[target.id] ?? <String>[];
    if (options.isEmpty) {
      return;
    }
    final String? selected = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        int? selectedIndex;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            return AlertDialog(
              title: const Text('重说结果'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int i) {
                    return RadioListTile<int>(
                      value: i,
                      groupValue: selectedIndex,
                      onChanged: (int? value) => setDialogState(() => selectedIndex = value),
                      title: Text(options[i]),
                    );
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('retry'),
                  child: const Text('再试三次'),
                ),
                FilledButton(
                  onPressed: selectedIndex == null
                      ? null
                      : () => Navigator.of(context).pop(options[selectedIndex!]),
                  child: const Text('使用此回复'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null) {
      return;
    }
    if (selected == 'retry') {
      await _retryAssistantAt(index);
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
  }
}
