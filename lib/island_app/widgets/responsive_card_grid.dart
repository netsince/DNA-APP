import 'package:flutter/material.dart';

import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:dna/theme/tokens.dart';

// ---- 角色卡网格的唯一一套列数/尺寸算法（审计 3.3 收敛点）----
//
// 之前这套算法在四个地方各写了一遍：
// * 本文件（SliverGrid + minColumnWidth）；
// * 搜索页写死 maxCrossAxisExtent 220 与 childAspectRatio 0.62；
// * 探索页骨架屏、首页骨架屏各写一遍 (width ~/ 200).clamp(2, 6)。
// 结果三者算出来的列数与格子高度互不相同，骨架屏换成真实网格时会跳一下。
// 现在只有这里一份：真实网格、骨架屏、搜索页都调 [cardGridMetrics]。

/// 列间/行间距（与旧实现保持一致：12）。
const double kCardGridSpacing = AppSpacing.md;

/// 最少列数。
const int kCardGridMinColumns = 2;

/// 最多列数。
const int kCardGridMaxColumns = 6;

/// 单列最小宽度（默认值，调用方可覆盖）。
const double kCardGridMinColumnWidth = 200;

/// 卡片文字区高度估算：封面 3:4 下方还要放名称/简介/统计。
const double kCardGridCaptionHeight = 96;

/// 单张卡片的高度：3:4 封面 + 文字区。
double cardGridCellHeight(double cellWidth) =>
    cellWidth * 4 / 3 + kCardGridCaptionHeight;

/// 一套网格版式：列数 + 单格宽高（由宽度推导）。
class CardGridMetrics {
  const CardGridMetrics({
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
  });

  final int columns;
  final double cellWidth;
  final double cellHeight;

  /// 直接喂给 [SliverGridDelegateWithFixedCrossAxisCount.childAspectRatio]。
  double get childAspectRatio =>
      cellWidth <= 0 || cellHeight <= 0 ? 1 : cellWidth / cellHeight;
}

/// 按可用宽度算列数与单格宽高（**纯函数**，骨架屏/搜索页/真实网格共用）。
///
/// 列数 = 宽度能放下几个 [minColumnWidth]，再夹在 minColumns..maxColumns；
/// 单格宽度扣掉列间距，高度按 [cardGridCellHeight] 估算。
CardGridMetrics cardGridMetrics(
  double availableWidth, {
  double minColumnWidth = kCardGridMinColumnWidth,
  int minColumns = kCardGridMinColumns,
  int maxColumns = kCardGridMaxColumns,
  double spacing = kCardGridSpacing,
}) {
  // 宽度未知（0 / 无限）时退回最小列数，避免除零与 NaN 传到布局层。
  final double width = (availableWidth.isFinite && availableWidth > 0)
      ? availableWidth
      : minColumnWidth * minColumns;
  final int columns = (width ~/ minColumnWidth).clamp(minColumns, maxColumns);
  final double cellWidth = (width - spacing * (columns - 1)) / columns;
  return CardGridMetrics(
    columns: columns,
    cellWidth: cellWidth,
    cellHeight: cardGridCellHeight(cellWidth),
  );
}

/// 响应式角色卡网格（对齐审计 P2：抽掉 explore/home/me/我的收藏 四处重复的
/// 「宽度自适应列数 + SliverGrid + CardTile」逻辑）。
///
/// 最少 2 列、最多 6 列，按可用宽度自适应；封面 3:4 + 下方文字区按列宽估算高度。
/// 列数算法见 [cardGridMetrics]（**唯一实现**）。
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.cards,
    this.onCardTap,
    this.minColumnWidth = kCardGridMinColumnWidth,
    this.maxColumns = kCardGridMaxColumns,
  });

  /// 卡片摘要 Map 列表（含 id/name/...，透传给 [CardTile]）。
  final List<Map<String, dynamic>> cards;

  /// 点开某张卡片；入参为卡片 id。为 null 时用 [CardTile] 内置的详情页打开。
  final void Function(String id)? onCardTap;

  /// 单列最小宽度（决定自适应列数）。
  final double minColumnWidth;

  /// 最大列数。
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final CardGridMetrics m = cardGridMetrics(
          constraints.crossAxisExtent,
          minColumnWidth: minColumnWidth,
          maxColumns: maxColumns,
        );
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: m.columns,
            mainAxisSpacing: kCardGridSpacing,
            crossAxisSpacing: kCardGridSpacing,
            childAspectRatio: m.childAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => CardTile(
              card: cards[index],
              onTap: onCardTap == null
                  ? null
                  : () => onCardTap!((cards[index]['id'] ?? '').toString()),
            ),
            childCount: cards.length,
          ),
        );
      },
    );
  }
}