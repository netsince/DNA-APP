import 'package:flutter/material.dart';

import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/status_badge.dart';
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

  /// 保留的公开参数：**当前没有任何调用点传它**。
  ///
  /// 状态徽章是只读指示，不是控件 —— 它原来挂着一个裸 `GestureDetector`，
  /// 命中区只有约 14dp 高，也没有任何语义（审计 4.3）。若将来真要让状态可点，
  /// 应该换成行内的 `IconButton`/菜单项，而不是把点击挂在徽章上。
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
                    _statusBadge(),
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
                    height: AppLineHeight.title,
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
                      StatusBadge(label: n),
                    if (world.entryCount > 3)
                      StatusBadge(label: '+${world.entryCount - 3}'),
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
                          fontSize: AppFontSize.tiny,
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

  /// 审核状态徽章：状态 → (语义色调, 图标)。
  ///
  /// 图标是颜色之外的第二通道（色觉障碍用户靠它区分）；`semanticLabel`
  /// 让读屏念成「审核状态：审核中」而不是孤零零三个字。徽章**只读**，
  /// 不挂手势（原来那枚裸 GestureDetector 的命中区只有约 14dp，审计 4.3）。
  Widget _statusBadge() {
    // 状态 → (色调, 图标) 的映射只有一份：[worldStatusStyle]。
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
}
