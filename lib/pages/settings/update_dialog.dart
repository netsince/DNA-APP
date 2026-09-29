// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/services/update_service.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

/// 更新提示弹窗。
///
/// 显示**远端版本号、发布时间、更新日志**,以及两个按钮:
/// * **前往更新** —— 用系统浏览器打开官网下载页(应用内不做任何下载);
/// * **忽略** —— 关掉弹窗。
///
/// 由 [showUpdateDialog] 弹出。
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  /// 格式化发布时间。取不到时显示「未知」。
  String get _published {
    final DateTime? t = info.publishedAt;
    if (t == null) return '未知';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _openDownload(BuildContext context) async {
    final Uri? uri = Uri.tryParse(UpdateService.downloadPage);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.system_update_alt, color: cs.primary),
          AppSpacing.wSm,
          const FitText('发现新版本'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ===== 版本号 =====
              _row(
                cs,
                Icons.new_releases_outlined,
                '最新版本',
                'v${info.remoteVersion}',
                highlight: true,
              ),
              AppSpacing.hSm,
              _row(
                cs,
                Icons.history,
                '当前版本',
                'v${info.localVersion.isEmpty ? "未知" : info.localVersion}',
              ),
              AppSpacing.hSm,
              _row(cs, Icons.schedule, '发布时间', _published),

              AppSpacing.hLg,
              const Divider(height: 1),
              AppSpacing.hMd,

              // ===== 更新日志 =====
              FitText('更新日志',
                  style: ts.titleSmall
                      ?.copyWith(fontWeight: AppWeight.medium)),
              AppSpacing.hSm,
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 240),
                padding: AppInsets.card,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: AppRadius.smAll,
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: SelectableText(
                  info.changelog.trim().isEmpty
                      ? '(本次发布未提供更新日志)'
                      : info.changelog.trim(),
                  style: ts.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const FitText('忽略'),
        ),
        FilledButton.icon(
          onPressed: () => _openDownload(context),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const FitText('前往更新'),
        ),
      ],
    );
  }

  /// 一行「图标 + 标签 + 值」。
  Widget _row(
    ColorScheme cs,
    IconData icon,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppSize.iconCard, color: cs.onSurfaceVariant),
        AppSpacing.wSm,
        SizedBox(
          width: 64,
          child: FitText(label,
              style: TextStyle(
                  fontSize: AppFontSize.caption, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: FitText(
            value,
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: highlight ? AppWeight.medium : AppWeight.regular,
              color: highlight ? cs.primary : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// 弹出更新提示。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => UpdateDialog(info: info),
  );
}
