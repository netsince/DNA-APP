import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 设置分组卡片(设计规范 5.3)。
///
/// 统一「一个设置分组 = 一张卡片」的视觉语序:
/// ```
/// [Icon(20, primary)] + [标题 titleMedium w700]
///               ↓ AppSpacing.xs
///         [说明文字 bodySmall, outline]
///               ↓ AppSpacing.sm
///         [设置项 ...]
/// ```
///
/// 卡片本身的圆角/描边/间距/外边距由全局 `cardTheme` 提供,
/// 业务代码不应再手写 `elevation` / `shape` / `margin`。
///
/// 用法:
/// ```dart
/// SettingSection(
///   icon: Icons.fingerprint,
///   title: '生物识别与密码保护',
///   description: '使用指纹、面容或系统锁屏密码保护应用隐私。',
///   children: <Widget>[
///     SettingSwitch(title: '进入应用需验证', value: v, onChanged: ...),
///   ],
/// )
/// ```
class SettingSection extends StatelessWidget {
  const SettingSection({
    super.key,
    this.icon,
    required this.title,
    this.description,
    required this.children,
    this.trailing,
  });

  /// 分组图标(使用 [AppSize.iconCard] 尺寸)。
  final IconData? icon;

  /// 分组标题。
  final String title;

  /// 分组说明(可选)。
  final String? description;

  /// 分组内的设置项。
  final List<Widget> children;

  /// 标题右侧的附加控件(可选)。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: AppInsets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, color: cs.primary, size: AppSize.iconCard),
                  AppSpacing.wSm,
                ],
                Expanded(
                  child: FitText(
                    title,
                    style: ts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (description != null) ...<Widget>[
              AppSpacing.hXs,
              FitText(
                description!,
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
            AppSpacing.hSm,
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 设置开关项。
///
/// 统一列表项内边距,避免各页手写 `SwitchListTile` + `contentPadding`。
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: FitText(title),
      subtitle: subtitle == null ? null : FitText(subtitle!),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// 可点击的导航设置项。
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return ListTile(
      enabled: enabled,
      leading: icon == null
          ? null
          : Container(
              width: AppSize.iconBox,
              height: AppSize.iconBox,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: AppAlpha.half),
                borderRadius: AppRadius.xsAll,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
            ),
      title: FitText(title),
      subtitle: subtitle == null ? null : FitText(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: enabled ? onTap : null,
    );
  }
}

/// 设置项内联说明/警告文字。
class SettingHint extends StatelessWidget {
  const SettingHint(
    this.text, {
    super.key,
    this.icon,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color effective = color ?? cs.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSize.iconInline, color: effective),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: FitText(text, style: TextStyle(color: effective, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
