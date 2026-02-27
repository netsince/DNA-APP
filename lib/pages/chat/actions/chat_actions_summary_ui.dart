part of '../../chat_page.dart';

mixin ChatActionsSummaryUi on ChatStateMixin {
  ConversationSummary? _summaryById(String? summaryId);

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
}
