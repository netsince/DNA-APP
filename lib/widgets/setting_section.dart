import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_surface.dart';
import 'fit_text.dart';

/// 设置分组 section（设计规范 5.3；按审计 3.3 / 4.2 修订为无容器）。
///
/// **不再「每组一张卡」**：分组是一串同构的项，不是「可整体操作的内容单元」。
/// 给每组套卡片，等于用容器（描边 / 圆角 / 卡片间距）代替**字号阶 + 间距**
/// 来表达层级 —— 一页七八个框，反而没有重点。
///
/// 现在的语序（纯排版，无容器）：
/// ```
/// [Icon(20, onSurfaceVariant)] + [标题 titleSmall w500, onSurfaceVariant]
///               ↓ AppSpacing.xs
///         [说明文字 bodySmall, onSurfaceVariant]
///               ↓ AppSpacing.sm
///         [设置项 ...]
///               ↓ AppSpacing.xl（组间距，由本组件自带）
/// ```
///
/// 水平内边距固定 [AppSpacing.lg]：与旧卡片内的 padding 相同，
/// 所以各 `*_spec` 调用点的横向排版不变；组间距也由本组件负责，
/// 页面不需要在 section 之间再插 `SizedBox`。
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
    this.collapsible = true,
    this.initiallyExpanded = true,
    this.padding,
    this.margin,
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

  /// 分组内容是否可折叠（默认可以）。
  ///
  /// 渐进式披露的最后一层：一页七八个分组时，收起态只留标题 + 说明，
  /// 用户按需展开自己关心的那组。传 false 用于「内容本身就是主体」的页面
  /// （例如存储空间的统计块），那种折叠起来反而多一步点击。
  final bool collapsible;

  /// 初始是否展开（仅 [collapsible] 为 true 时有意义）。
  final bool initiallyExpanded;

  /// 外层内边距。为 null 时用设置页的默认值（左右 lg、上下 md）。
  ///
  /// 给「不在设置页里、但想复用分组头」的页面用（编辑器类的表单页面通常已有
  /// 自己的 `bodyPadding`，再叠一层就会多出一段横向留白）。
  final EdgeInsetsGeometry? padding;

  /// 外层外边距。为 null 时用默认值（底部 md 作为组间距）。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    final Widget header = Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          // 图标不再用 primary：primary 是交互/选中色，
          // 静态分组头用 onSurfaceVariant（审计 4.2）。
          Icon(
            icon,
            color: cs.onSurfaceVariant,
            size: AppSize.iconCard,
          ),
          AppSpacing.wSm,
        ],
        Expanded(
          child: FitText(
            title,
            style: ts.titleSmall?.copyWith(
              fontWeight: AppWeight.medium,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    );

    // 分组 = 一块有底色的区域；组与组之间靠间距分隔（不再靠描边卡片）。
    return AppSurface(
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.md),
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
      child: collapsible
            ? _CollapsibleSectionBody(
                header: header,
                description: description,
                initiallyExpanded: initiallyExpanded,
                children: children,
              )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                header,
                if (description != null) ...<Widget>[
                  AppSpacing.hXs,
                  FitText(
                    description!,
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                AppSpacing.hSm,
                ...children,
              ],
            ),
    );
  }
}

/// 可折叠分组的内容体。
///
/// 收起/展开只影响内容；标题始终可见（它是这一组的名字）。
/// 点击标题行切换，右侧 chevron 跟着转 90°，给一个「这里能收」的暗示。
class _CollapsibleSectionBody extends StatefulWidget {
  const _CollapsibleSectionBody({
    required this.header,
    required this.description,
    required this.initiallyExpanded,
    required this.children,
  });

  final Widget header;
  final String? description;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_CollapsibleSectionBody> createState() =>
      _CollapsibleSectionBodyState();
}

class _CollapsibleSectionBodyState extends State<_CollapsibleSectionBody> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Semantics(
            button: true,
            expanded: _expanded,
            child: Row(
              children: <Widget>[
                Expanded(child: widget.header),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more,
                    size: AppSize.iconCard,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.description != null) ...<Widget>[
          AppSpacing.hXs,
          FitText(
            widget.description!,
            style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        AnimatedCrossFade(
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppSpacing.hSm,
              ...widget.children,
            ],
          ),
          secondChild: const SizedBox(width: double.infinity),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}

/// 设置开关项。
///
/// 统一列表项内边距,避免各页手写 `SwitchListTile` + `contentPadding`。
///
/// **说明文字的两种位置**(见 `SETTINGS_AUDIT.md` 规矩 3):
/// * [subtitle] —— 一句话价值(短),单独一行放在标题下方;
/// * [description] —— 更短的补充(≤ 10 字,如「仅本条」「不推荐」),
///   右对齐到开关左侧的同一行。这样开关行**仍然只占一行高度**,
///   不会因为一句短说明把列表撑成双行。
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    this.subtitle,
    this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;

  /// 行内短说明(右对齐,与开关同一行)。
  final String? description;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: FitText(title),
      subtitle: subtitle == null ? null : FitText(subtitle!),
      secondary: description == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppSpacing.wSm,
                Flexible(
                  child: FitText(
                    description!,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.caption(Theme.of(context))
                        .copyWith(color: cs.outline),
                  ),
                ),
              ],
            ),
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
              child: Icon(
                icon,
                color: cs.onPrimaryContainer,
                size: AppSize.iconCard,
              ),
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
            AppSpacing.wSm,
          ],
          Expanded(
            child: FitText(
              text,
              style: TextStyle(color: effective, fontSize: AppFontSize.caption),
            ),
          ),
        ],
      ),
    );
  }
}
