import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 详情页「区块」的两种既有画法。
///
/// 为什么有两种：卡片详情用描边圆角卡包住正文（内容重、需要分隔），
/// 角色展示用『小标题 + 正文』平铺（一屏读下来）。强行统一会改掉观感，
/// 所以这里只统一**描述**（有没有内容、顺序、图标），画法各留一份。
enum DetailSectionStyle {
  /// 描边圆角卡 + 图标 + 标题 + 浅底正文（卡片详情）。
  outlinedCard,

  /// 无容器：小标题（primary）+ 正文（卡片详情之外的展示页）。
  plainHeading,
}

/// 详情页的一个区块：可见条件由 [visible] 决定（默认按正文是否为空自动判断）。
class DetailSectionSpec {
  const DetailSectionSpec({
    required this.id,
    required this.title,
    this.body = '',
    this.icon,
    this.visible,
    this.custom,
  });

  final String id;
  final String title;
  final String body;

  /// 图标（[DetailSectionStyle.outlinedCard] 用；plainHeading 忽略）。
  final IconData? icon;

  /// 显式可见性；不传时 = 正文非空（或给了 [custom]）。
  final bool? visible;

  /// 自定义内容（对话示例、作者注释、外链按钮这类不是纯文本的区块）。
  final Widget? custom;

  bool get isVisible =>
      visible ?? (custom != null || body.trim().isNotEmpty);
}

/// 把一组 [DetailSectionSpec] 渲染成 widget 列表（空值的区块自动不占位）。
///
/// 返回值用 `...` 展开进 Column / ListView 的 children。
class DetailSections {
  const DetailSections._();

  static List<Widget> buildAll(
    List<DetailSectionSpec> sections, {
    DetailSectionStyle style = DetailSectionStyle.outlinedCard,
  }) {
    return <Widget>[
      for (final DetailSectionSpec s in sections)
        if (s.isVisible)
          s.custom ??
              (style == DetailSectionStyle.outlinedCard
                  ? _OutlinedCardSection(spec: s)
                  : _PlainHeadingSection(spec: s)),
    ];
  }
}

/// 描边圆角卡 + 图标 + 标题 + 浅底正文（与卡片详情原来的 `_ContentSection` 逐像素一致）。
class _OutlinedCardSection extends StatelessWidget {
  const _OutlinedCardSection({required this.spec});

  final DetailSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: <Widget>[
                if (spec.icon != null) ...<Widget>[
                  Icon(spec.icon, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    spec.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.02,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              spec.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: AppLineHeight.reading,
                wordSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 无容器：小标题（primary）+ 正文（与角色展示原来的 `_section` 一致）。
class _PlainHeadingSection extends StatelessWidget {
  const _PlainHeadingSection({required this.spec});

  final DetailSectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(
            spec.title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          FitText(
            spec.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: AppLineHeight.body,
            ),
          ),
        ],
      ),
    );
  }
}
