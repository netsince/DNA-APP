import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 全局统一的空态 / 错误态 / 加载态。
///
/// 这三个状态在项目里曾经各写各的：主程序只有 [AppEmptyState]，
/// 加载与错误靠散落的 `CircularProgressIndicator` 或手拼「图标+文字+重试」；
/// 社区另有一套 `EmptyState`/`ErrorState`/`LoadingState`（三态齐全、有 compact，
/// 但图标尺寸、间距、字号都是硬编码）。
///
/// 这里是**唯一实现**：主程序的 `app_empty_state.dart` 与社区的
/// `island_app/widgets/state_views.dart` 都只 `export` 本文件，不再各自定义。
///
/// 规范见 `DESIGN_SPEC.md` 5.4：图标 48(outline) + 标题 bodyLarge +
/// 说明 bodySmall + 可选按钮。文字一律 [FitText]。

/// 空态：图标 + 标题 + 可选说明 + 可选操作。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.compact = false,
  });

  /// 图标。为 null 时只显示文字（如「已选定当前模型」这类不算空态的空态）。
  final IconData? icon;

  /// 主提示文字。
  final String title;

  /// 补充说明。
  final String? description;

  /// [description] 的别名。
  ///
  /// 社区的旧 API 用的是 `message`，为免改动既有调用点，这里保留为同义参数。
  /// 新代码一律用 [description]。
  final String? message;

  /// 操作按钮文案（提供时需同时提供 [onAction]）。
  final String? actionLabel;

  /// 操作按钮回调。
  final VoidCallback? onAction;

  /// 操作按钮图标（可选）。
  final IconData? actionIcon;

  /// 紧凑模式：图标取 [AppSize.iconEmptyCompact]，用于嵌在卡片/网格/列表里的空态。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String? body = description ?? message;
    return _StateLayout(
      icon: icon,
      iconSize: compact ? AppSize.iconEmptyCompact : AppSize.iconEmpty,
      title: title,
      body: body,
      actionLabel: actionLabel,
      onAction: onAction,
      actionIcon: actionIcon,
      // 空态的主操作是「去创建/去发布」，用 FilledButton（主操作层级）。
      primaryAction: true,
    );
  }
}

/// 错误态：固定断线图标 + 失败说明 + 可选重试。
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message = '加载失败',
    this.onRetry,
    this.compact = false,
  });

  /// 失败说明。
  final String message;

  /// 重试回调。为 null 时不显示按钮。
  final VoidCallback? onRetry;

  /// 紧凑模式：用于嵌在卡片/网格/列表里的错误。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: Icons.cloud_off_outlined,
      // 错误态与空态同级：整页都是 48，不能让错误提示看着比空态轻。
      iconSize: compact ? AppSize.iconEmptyCompact : AppSize.iconEmpty,
      title: message,
      actionLabel: onRetry == null ? null : '重试',
      onAction: onRetry,
      // 错误态的重试是次操作（用户可以不重试直接离开），用 OutlinedButton。
      primaryAction: false,
    );
  }
}

/// 加载态：居中转圈，可选提示文字。
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message});

  /// 转圈下方的提示文字（可选）。
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          if (message != null && message!.isNotEmpty) ...<Widget>[
            AppSpacing.hMd,
            FitText(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空态与错误态共用的布局：图标 + 标题 + 说明 + 按钮。
///
/// 抽出来是为了让两种态**只在图标、按钮层级上不同**，
/// 间距与字号永远一致 ——否则又是两份会各自漂移的实现。
class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.iconSize,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    required this.primaryAction,
  });

  final IconData? icon;
  final double iconSize;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final bool primaryAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: AppInsets.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: iconSize, color: scheme.outline),
              AppSpacing.hLg,
            ],
            // 标题走 bodyLarge（DESIGN_SPEC 5.4）；不额外加粗，
            // 内置字体只有 400/500 两个真实字重，合成加粗会糊。
            FitText(title, textAlign: TextAlign.center, style: text.bodyLarge),
            if (body != null && body!.isNotEmpty) ...<Widget>[
              AppSpacing.hXs,
              FitText(
                body!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              AppSpacing.hLg,
              _buildAction(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction() {
    if (primaryAction) {
      return actionIcon == null
          ? FilledButton(
              onPressed: onAction,
              child: FitText(actionLabel!),
            )
          : FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: FitText(actionLabel!),
            );
    }
    return OutlinedButton(onPressed: onAction, child: FitText(actionLabel!));
  }
}
