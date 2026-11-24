import 'package:material_ui/material_ui.dart';

import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/widgets/status_badge.dart';
import 'package:dna/theme/tokens.dart';

/// 世界的**紧凑行**：给「列表语境」用（我的内容 / 搜索结果）。
///
/// ## 为什么世界有两种形态（这不是没统一）
///
/// 同一个世界实体，在两个场景里读法完全不同：
///
/// | 场景 | 用户任务 | 形态 | 为什么 |
/// |---|---|---|---|
/// | 世界栏目 / 发现 | 逛、比较、挑一个 | [WorldCardTile]（瀑布流卡片） | 视觉优先：卡片能排开简介、词条名、标签，多列并排才比得出来 |
/// | 我的内容 / 搜索结果 | 找一件我已知的东西 | **本组件**（单行 + 副标题 + chevron） | 扫读优先：密度优先，一屏多列几条，chevron 说明「点进去」 |
///
/// 所以两种形态是**有意的语义区分**：用卡片的地方是「浏览」，用行的地方是
/// 「定位」。真正的重复是**同一场景内的重复** —— 以前「我的」页与搜索结果各自
/// 手写了一遍 `ListTile`，元信息口径（哪些字段、怎么拼）还不一样；现在两处共用这里。
///
/// ## 元信息口径
///
/// 与 [WorldCardTile] 保持同一套字段，只是压缩成一行：
/// 词条数 · 体积 · 复制数 [ · 调用方补充字段 ] [ · #标签 ×2]。
/// 审核状态用只读的 [StatusBadge]，不抢名称的注意力。
class WorldListTile extends StatelessWidget {
  const WorldListTile({
    super.key,
    required this.world,
    required this.onTap,
    this.leadingIcon,
    this.showStatus = false,
    this.extraMeta,
  });

  /// 世界卡摘要（列表接口给的元信息，不含正文）。
  final WorldCardSummary world;

  final VoidCallback onTap;

  /// 左侧图标（可选）。搜索结果给 `Icons.public_outlined` 提示「这是一条世界」，
  /// 「我的内容」不给 —— 那里的上下文已经说明了类型，多一个图标只是噪音。
  final IconData? leadingIcon;

  /// 是否显示审核状态徽章（只有自己的条目才有意义）。
  final bool showStatus;

  /// 追加到元信息尾部的字段：
  /// * 「我的内容」传创建时间的相对描述（「3 天前」）；
  /// * 搜索结果传作者名（搜索结果里「是谁写的」比「什么时候建的」更有用）。
  final String? extraMeta;

  /// 审核状态 → 只读徽章。
  ///
  /// 状态 → (色调, 图标) 的映射只有一份：[worldStatusStyle]。
  Widget _statusBadge() {
    final ({BadgeTone tone, IconData icon}) style = worldStatusStyle(
      status: world.status,
      hidden: world.isHidden,
    );
    return StatusBadge(
      label: world.statusLabel,
      icon: style.icon,
      tone: style.tone,
      semanticLabel: '审核状态：${world.statusLabel}',
    );
  }

  /// 一行元信息：词条数 · 体积 · 复制数 · 补充字段 · #标签。
  String get _metaLine {
    final List<String> parts = <String>[
      if (world.entryCount > 0) '${world.entryCount} 词条',
      if (world.sizeLabel.isNotEmpty) world.sizeLabel,
      if (world.copyCount > 0) '复制 ${world.copyCount}',
      if (extraMeta != null && extraMeta!.isNotEmpty) extraMeta!,
      for (final String t in world.tags.take(2)) '#$t',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool hasStatus = showStatus && world.statusLabel.isNotEmpty;
    final String meta = _metaLine;

    return ListTile(
      leading: leadingIcon == null
          ? null
          : Icon(leadingIcon, color: cs.onSurfaceVariant),
      title: Text(
        world.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: AppWeight.medium,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (world.summary.isNotEmpty)
            Text(
              world.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
            ),
          if (hasStatus) ...<Widget>[
            AppSpacing.hXxs,
            Align(alignment: Alignment.centerLeft, child: _statusBadge()),
          ],
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}