import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 空状态占位组件(设计规范 5.4)。
///
/// 统一各页面手写的 `Center > Column > FitText + FilledButton` 结构:
/// 图标(48, outline) + 标题 + 说明 + 可选操作按钮。
///
/// 用法:
/// ```dart
/// AppEmptyState(
///   icon: Icons.people_outline,
///   title: '暂无TA，先创建一个吧。',
///   actionLabel: '创建TA',
///   onAction: _createTa,
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  /// 空状态图标。
  final IconData? icon;

  /// 主提示文字。
  final String title;

  /// 补充说明(可选)。
  final String? description;

  /// 操作按钮文案(可选,提供时需同时提供 [onAction])。
  final String? actionLabel;

  /// 操作按钮回调。
  final VoidCallback? onAction;

  /// 操作按钮图标(可选)。
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: AppInsets.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: AppSize.iconEmpty, color: cs.outline),
              AppSpacing.hLg,
            ],
            FitText(title, textAlign: TextAlign.center, style: ts.bodyLarge),
            if (description != null) ...<Widget>[
              AppSpacing.hXs,
              FitText(
                description!,
                textAlign: TextAlign.center,
                style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              AppSpacing.hLg,
              actionIcon == null
                  ? FilledButton(
                      onPressed: onAction,
                      child: FitText(actionLabel!),
                    )
                  : FilledButton.icon(
                      onPressed: onAction,
                      icon: Icon(actionIcon),
                      label: FitText(actionLabel!),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
