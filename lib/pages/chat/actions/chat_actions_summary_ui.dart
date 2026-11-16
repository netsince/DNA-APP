part of '../../chat_page.dart';

mixin ChatActionsSummaryUi on ChatStateMixin {
  ConversationSummary? _summaryById(String? summaryId);

  // ignore: unused_element
  Future<void> _showSummaryDetail(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    await showInfoDialog(
      context: context,
      title: '对话摘要',
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: FitText(summary.text),
        ),
      ),
    );
  }

  // ignore: unused_element
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

  // ignore: unused_element
  Future<void> _editSummary(String summaryId) async {
    final ConversationSummary? summary = _summaryById(summaryId);
    if (summary == null) {
      return;
    }
    // 长文本编辑不是「需要明确决定」的模态阻断，用 dialog 装 4~10 行输入框
    // 既看不全也不好改；改成带键盘避让的 sheet（审计 3.2，与项目里世界词条
    // 编辑的做法一致）。返回语义不变：保存回传新文本，取消回传 null。
    final String? updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _SummaryEditSheet(
        initialText: summary.text,
        accentTheme: _accentTheme,
      ),
    );
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

/// 「编辑摘要」的 sheet：多行输入 + 键盘避让。
///
/// 控制器由 sheet 自己持有、随 sheet 一起 dispose（不在调用方创建，
/// 否则关闭动画期间可能被提前释放）。
class _SummaryEditSheet extends StatefulWidget {
  const _SummaryEditSheet({
    required this.initialText,
    required this.accentTheme,
  });

  final String initialText;
  final ThemeData accentTheme;

  @override
  State<_SummaryEditSheet> createState() => _SummaryEditSheetState();
}

class _SummaryEditSheetState extends State<_SummaryEditSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: widget.accentTheme,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FitText('编辑摘要', style: theme.textTheme.titleMedium),
              AppSpacing.hMd,
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText: '输入新的摘要内容',
                  border: OutlineInputBorder(),
                ),
              ),
              AppSpacing.hLg,
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const FitText('取消'),
                    ),
                  ),
                  AppSpacing.wMd,
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text),
                      child: const FitText('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
