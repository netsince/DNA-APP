import 'package:flutter/material.dart';

/// 举报底部表单：选择原因（可选补充说明）后提交。
///
/// 角色卡与世界卡共用同一份 —— 举报流程不该因为对象不同而分叉。
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.reasons,
    required this.onSubmitted,
    this.title = '举报',
  });

  final List<({String key, String label})> reasons;
  final void Function(String key, String detail) onSubmitted;

  /// 表单标题，例如「举报角色卡」「举报世界卡」。
  final String title;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  String? _selected;
  final TextEditingController _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final r in widget.reasons)
                        InkWell(
                          onTap: () => setState(() => _selected = r.key),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  _selected == r.key
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 20,
                                  color: _selected == r.key
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Text(r.label),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '补充说明（可选）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () =>
                        widget.onSubmitted(_selected!, _detailCtrl.text.trim()),
                child: const Text('提交举报'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
