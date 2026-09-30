import 'package:flutter/material.dart';

import 'package:dna/island_app/widgets/card_tile.dart';

/// 响应式角色卡网格（对齐审计 P2：抽掉 explore/home/me/我的收藏 四处重复的
/// 「宽度自适应列数 + SliverGrid + CardTile」逻辑）。
///
/// 最少 2 列、最多 6 列，按可用宽度自适应；封面 3:4 + 下方文字区按列宽估算高度，
/// 与既有页面行为一致。
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.cards,
    this.onCardTap,
    this.minColumnWidth = 200,
    this.maxColumns = 6,
  });

  /// 卡片摘要 Map 列表（含 id/name/...，透传给 [CardTile]）。
  final List<Map<String, dynamic>> cards;

  /// 点开某张卡片；入参为卡片 id。为 null 时用 [CardTile] 内置的详情页打开。
  final void Function(String id)? onCardTap;

  /// 单列最小宽度（决定自适应列数）。
  final double minColumnWidth;

  /// 最大列数。
  final int maxColumns;

  static const int _minColumns = 2;
  static const double _spacing = 12.0;

  /// 估算单张卡片高度（封面 3:4 + 下方文字区 ~96）。
  static double _cellHeight(double cellWidth) => cellWidth * 4 / 3 + 96;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = (width ~/ minColumnWidth).clamp(_minColumns, maxColumns);
        final cellWidth = (width - _spacing * (columns - 1)) / columns;
        final cellHeight = _cellHeight(cellWidth);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: _spacing,
            crossAxisSpacing: _spacing,
            childAspectRatio: cellWidth / cellHeight,
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
