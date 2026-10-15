import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 配置类表单的检测结果横幅：容器 + 图标 + 文字。
///
/// 成功用 primaryContainer、失败用 errorContainer —— 两套都随明暗主题自动
/// 换色，不会出现「浅色主题下写死的深绿落到深色底上」的对比度问题。
///
/// OOBE 的 API / 社区两步、设置页的 AI 服务（精简模式）、社区的两个服务器
/// 地址设置页，原先各自用裸色文字或 errorText 表达结果；现在四处共用本组件，
/// 结果提示从此同一种长相。
class ConfigStatusBanner extends StatelessWidget {
  const ConfigStatusBanner({
    super.key,
    required this.message,
    this.isError = false,
  });

  /// 提示文案（成功或失败的原始信息）。
  final String message;

  /// true = 失败态（errorContainer + 错误图标）。
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color background = isError ? cs.errorContainer : cs.primaryContainer;
    final Color foreground = isError
        ? cs.onErrorContainer
        : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: AppSize.iconInline,
            color: foreground,
          ),
          AppSpacing.wSm,
          Expanded(
            child: FitText(
              message,
              style: AppTextStyles.caption(
                theme,
              ).copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
