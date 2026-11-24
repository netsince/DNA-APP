import 'package:flutter/material.dart';

import 'package:dna/widgets/fit_text.dart';

/// 候选弹框底部的三按钮栏：取消 / 再生成 / 使用。
///
/// 「重说结果」与「灵感列表」两张表的这一行原本各写一遍（布局、间距、
/// 安全区避让完全一致，只差文案与禁用条件）。抽出来只收这一行——
/// **不做整表合并**：两张表的状态机语义不同（重说是「再试只追加」，
/// 灵感是「换主题清空旧候选」），合并会把差异变成一堆开关参数。
class CandidateActionBar extends StatelessWidget {
  const CandidateActionBar({
    super.key,
    required this.onCancel,
    required this.onRegenerate,
    required this.onConfirm,
    required this.cancelLabel,
    required this.regenerateLabel,
    this.confirmLabel = '使用',
    this.busy = false,
    this.showRegenerateSpinner = false,
    this.regenerateEnabled = true,
    this.confirmEnabled = true,
    this.bottomInset = 0,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onRegenerate;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final String regenerateLabel;
  final String confirmLabel;

  /// 生成中：三个按钮一起禁用（两张表在请求进行时都不允许操作）。
  final bool busy;

  /// 再生成按钮是否把图标换成小转圈并把文案换成「生成中…」。
  /// 「重说结果」表这么做，「灵感列表」表保持原样（只禁用、不换图标）。
  final bool showRegenerateSpinner;
  final bool regenerateEnabled;
  final bool confirmEnabled;

  /// 底部安全区（键盘/手势条）避让。
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onCancel,
              child: FitText(cancelLabel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: busy || !regenerateEnabled ? null : onRegenerate,
              icon: (busy && showRegenerateSpinner)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.autorenew),
              label: FitText(
                (busy && showRegenerateSpinner) ? '生成中…' : regenerateLabel,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: (!confirmEnabled || busy) ? null : onConfirm,
              child: FitText(confirmLabel),
            ),
          ),
        ],
      ),
    );
  }
}
