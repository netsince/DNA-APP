import 'package:flutter/material.dart';

import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/theme/tokens.dart';

/// 世界卡的卡片瓦片（列表 / 搜索 / 主页共用）。
///
/// 没有封面图，所以用「数据 + 内容」两条锚点立住形态：
/// * 内容：简介 + 前几个词条名
/// * 数据：词条数 / 体积 / 复制量
///
/// 高度**不固定**：列表用瀑布流，卡片按内容自然长短（简介两行、标签多少都会变），
/// 一排排齐反而显得死板。
class WorldCardTile extends StatelessWidget {
  const WorldCardTile({
    super.key,
    required this.world,
    required this.onTap,
    this.showStatus = false,
    this.onStatusTap,
  });

  final WorldCardSummary world;
  final VoidCallback onTap;

  /// 是否显示审核状态徽章（自己的条目才有意义）。
  final bool showStatus;
  final VoidCallback? onStatusTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String when = world.updatedAt == null
        ? ''
        : formatRelativeTime(world.updatedAt!.toIso8601String());

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        world.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                    ),
                    if (showStatus && world.statusLabel.isNotEmpty)
                      _StatusPill(
                        label: world.statusLabel,
                        status: world.status,
                        hidden: world.isHidden,
                        onTap: onStatusTap,
                      ),
                  ],
                ),
                if (world.summary.isNotEmpty) ...<Widget>[
                  AppSpacing.hXxs,
                  Text(
                    world.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
                if (world.previewNames.isNotEmpty) ...<Widget>[
                  AppSpacing.hXs,
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final String n in world.previewNames.take(3))
                        _EntryChip(name: n),
                      if (world.entryCount > 3)
                        _EntryChip(name: '+${world.entryCount - 3}', muted: true),
                    ],
                  ),
                ],
                if (world.tags.isNotEmpty) ...<Widget>[
                  AppSpacing.hXs,
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final String t in world.tags.take(3))
                        Text(
                          '#$t',
                          style: TextStyle(
                            fontSize: AppFontSize.caption - 1,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
                AppSpacing.hXs,
                Text(
                  <String>[
                    if (world.entryCount > 0) '${world.entryCount} 词条',
                    if (world.sizeLabel.isNotEmpty) world.sizeLabel,
                    if (world.copyCount > 0) '复制 ${world.copyCount}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (world.authorName.isNotEmpty) ...<Widget>[
                  AppSpacing.hXxs,
                  Row(
                    children: <Widget>[
                      Avatar(avatar: world.authorAvatar, radius: 8),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          world.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (when.isNotEmpty)
                        Text(
                          ' · $when',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}

/// 卡片上的词条名小片。
class _EntryChip extends StatelessWidget {
  const _EntryChip({required this.name, this.muted = false});

  final String name;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.xsAll,
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppFontSize.caption - 1,
          color: muted ? cs.onSurfaceVariant : cs.onSurface,
        ),
      ),
    );
  }
}

/// 审核状态小徽章（自己的条目）。
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.status,
    required this.hidden,
    this.onTap,
  });

  final String label;
  final String status;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      'approved' => hidden
          ? (cs.surfaceContainerHighest, cs.onSurfaceVariant)
          : (cs.primaryContainer, cs.onPrimaryContainer),
      'rejected' => (cs.errorContainer, cs.onErrorContainer),
      'deleted' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.tertiaryContainer, cs.onTertiaryContainer),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.xsAll),
        child: Text(
          label,
          style: TextStyle(fontSize: AppFontSize.caption - 1, color: fg),
        ),
      ),
    );
  }
}
