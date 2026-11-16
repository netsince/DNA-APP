import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 小标签的语义色调。
///
/// 只有这五档，**不允许调用方直接塞颜色**：一旦放开 raw color，就又回到
/// 「五套各自调色」的老路（审计 3.3 / 4.2 —— 社区模块曾有 _PinBadge /
/// _GenderBadge / _EntryChip / _StatusPill / _Chip 五份实现）。
enum BadgeTone {
  /// 中性元信息（作者、日期、词条名、标签）。surfaceContainerHighest。
  neutral,

  /// 正向 / 正常（已通过、性别）。primaryContainer。
  positive,

  /// 进行中 / 待处理（审核中）。tertiaryContainer。
  caution,

  /// 危险 / 被拒（已拒绝、处罚生效中）。errorContainer。
  danger,

  /// 提示性信息（置顶、已下架这类「额外说明」）。secondaryContainer。
  info,
}

/// 世界卡审核状态 → (色调, 图标)。**唯一一张映射表**。
///
/// 原来同一张表在三个文件里各写了一遍（`WorldCardTile` 的状态徽章、
/// `WorldStatusChip`、`WorldListTile`），任一处改档位就和另外两处不一致。
///
/// 档位语义（与网页版 `status_badge` 对齐）：
/// * `approved` + 未下架 → positive / check_circle
/// * `approved` + 已下架 → neutral / visibility_off（下架是中性状态，不是错误）
/// * `rejected` → danger / error
/// * `deleted`（已撤回）→ neutral / delete
/// * 其它（pending）→ caution / hourglass
///
/// 只返回色档与图标：**文案仍取 `WorldCardSummary.statusLabel`**（模型里的
/// 单一来源），免得同一句「待审核 / 已拒绝」在两处维护、慢慢漂开。
({BadgeTone tone, IconData icon}) worldStatusStyle({
  required String status,
  bool hidden = false,
}) {
  final (BadgeTone tone, IconData icon) = switch (status) {
    'approved' => hidden
        ? (BadgeTone.neutral, Icons.visibility_off_outlined)
        : (BadgeTone.positive, Icons.check_circle),
    'rejected' => (BadgeTone.danger, Icons.error),
    'deleted' => (BadgeTone.neutral, Icons.delete_outline),
    _ => (BadgeTone.caution, Icons.hourglass_empty),
  };
  return (tone: tone, icon: icon);
}

/// 只读的小标签（状态 / 元信息），全模块唯一实现。
///
/// ## 它不是控件
///
/// **没有 onTap、不出 ink、不响应点击**。M3 里 chip 是「可交互的紧凑元素」：
/// 把不可点的元信息做成 chip 外观，用户会一直去点它 —— `world_detail_page`
/// 里那个 `Chip(label: Text(tag))` 没有任何回调，就是最典型的例子（审计 3.3）。
///
/// 因此它刻意不满足 48dp 触摸目标：它不可点，不需要命中区；高度压在
/// 约 18dp，才能塞进卡片标题行、词条行这些密集位置。
///
/// ## 视觉由三件事决定
/// * [tone] —— 语义色对（背景 + 前景），保证暗色主题下自动成立；
/// * [icon] —— 非颜色通道：状态不能只靠底色区分（审计 4.3）；
/// * 字号令牌 —— labelSmall，不加粗（内置字体只有 400/500 两个真实字重）。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = BadgeTone.neutral,
    this.emphasized = false,
    this.semanticLabel,
  });

  /// 可见文案。
  final String label;

  /// 可选图标（16dp）。状态类徽章**建议都给**，作为颜色之外的第二通道。
  final IconData? icon;

  /// 语义色调。
  final BadgeTone tone;

  /// 加重：字重 500 + 一圈前景色细描边。
  ///
  /// 只给「叠在图片上」或「必须一眼看到」的那一枚（如封面上的置顶角标）。
  final bool emphasized;

  /// 读屏文案；为空时只念 [label] 本身。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color bg, Color fg) = _toneColors(theme.colorScheme);

    final Widget badge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.xsAll,
        border: emphasized
            ? Border.all(
                color: fg.withValues(alpha: AppAlpha.half),
                width: AppAlpha.half,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: AppSize.iconInline, color: fg),
            AppSpacing.wXs,
          ],
          // 用裸 Text 而不是 FitText：
          // * 徽章是短标签，**不该被 FittedBox 缩字**（审计 4.3：字体缩放被缩回）；
          // * FitText 会让 find.text 同一字符串命中两次（FitText 本身也是 Text），
          //   既有测试断言的是 findsOneWidget，换过来会平白多一处红。
          // 长内容（作者名、标签）由外层 Flexible 约束宽度，超出省略。
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: emphasized ? AppWeight.medium : null,
              ),
            ),
          ),
        ],
      ),
    );

    // 读屏只念一句完整的（图标 + 文案不拆成两段），且明确念成状态而不是按钮。
    return Semantics(
      label: semanticLabel ?? label,
      child: ExcludeSemantics(child: badge),
    );
  }

  /// 语义色调 → (背景, 前景)。
  (Color, Color) _toneColors(ColorScheme cs) => switch (tone) {
    BadgeTone.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    BadgeTone.positive => (cs.primaryContainer, cs.onPrimaryContainer),
    BadgeTone.caution => (cs.tertiaryContainer, cs.onTertiaryContainer),
    BadgeTone.danger => (cs.errorContainer, cs.onErrorContainer),
    BadgeTone.info => (cs.secondaryContainer, cs.onSecondaryContainer),
  };
}