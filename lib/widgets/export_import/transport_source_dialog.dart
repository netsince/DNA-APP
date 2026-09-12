import 'package:flutter/material.dart';

import 'package:dna/widgets/fit_text.dart';

/// 导出目的地。
enum ExportTarget {
  /// 复制到剪贴板(原有行为)。
  clipboard,

  /// 导出为文件(新增)。
  file,
}

/// 导入来源。
enum ImportSource {
  /// 从剪贴板读取(原有行为)。
  clipboard,

  /// 从文件读取(新增)。
  file,
}

/// 询问「导出到剪贴板还是导出到文件」。取消返回 null。
///
/// [extraOptions] 可插入额外的选项控件(如角色卡的「压缩图片」勾选),
/// 会被放在单选组之上。
Future<ExportTarget?> showExportTargetDialog({
  required BuildContext context,
  required String title,
  String? description,
  Widget? extraOptions,
}) async {
  ExportTarget target = ExportTarget.clipboard;
  return showDialog<ExportTarget>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setSB) => AlertDialog(
        title: FitText(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (extraOptions != null) ...<Widget>[
              extraOptions,
              const SizedBox(height: 8),
            ],
            if (description != null) ...<Widget>[
              FitText(
                description,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            RadioGroup<ExportTarget>(
              groupValue: target,
              onChanged: (ExportTarget? v) =>
                  setSB(() => target = v ?? ExportTarget.clipboard),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<ExportTarget>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: FitText('复制到剪贴板'),
                    subtitle: FitText('便于直接粘贴分享给他人'),
                    value: ExportTarget.clipboard,
                  ),
                  RadioListTile<ExportTarget>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: FitText('导出为文件'),
                    subtitle: FitText('可自行选择保存路径，便于归档与跨设备传递'),
                    value: ExportTarget.file,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, target),
            child: const FitText('导出'),
          ),
        ],
      ),
    ),
  );
}

/// 询问「从剪贴板导入还是从文件导入」。取消返回 null。
Future<ImportSource?> showImportSourceDialog({
  required BuildContext context,
  required String title,
  String? description,
}) async {
  ImportSource source = ImportSource.clipboard;
  return showDialog<ImportSource>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setSB) => AlertDialog(
        title: FitText(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (description != null) ...<Widget>[
              FitText(
                description,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            RadioGroup<ImportSource>(
              groupValue: source,
              onChanged: (ImportSource? v) =>
                  setSB(() => source = v ?? ImportSource.clipboard),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<ImportSource>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: FitText('从剪贴板导入'),
                    value: ImportSource.clipboard,
                  ),
                  RadioListTile<ImportSource>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: FitText('从文件导入'),
                    subtitle: FitText('选择此前导出的文件'),
                    value: ImportSource.file,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, source),
            child: const FitText('导入'),
          ),
        ],
      ),
    ),
  );
}
