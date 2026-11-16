import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/theme/tokens.dart';

/// `cardGridMetrics` 的契约（审计 3.3「网格列数三套算法」的收敛点）。
///
/// 这套算法同时供真实网格、骨架屏、搜索页使用 —— 三者必须算出**同一份**
/// 列数与格子尺寸，否则「骨架屏换成真实内容时会跳一下」这个老问题会回来。
/// 这类纯函数最该锁的就是边界：宽度未知、刚好一列、超过上限。
void main() {
  group('列数', () {
    test('按最小列宽算列数：600 宽 / 200 最小列宽 = 3 列', () {
      expect(cardGridMetrics(600).columns, 3);
    });

    test('窄窗口至少 2 列（不出现 1 列的大卡片）', () {
      expect(cardGridMetrics(320).columns, kCardGridMinColumns);
      expect(cardGridMetrics(200).columns, kCardGridMinColumns);
    });

    test('宽窗口夹在上限 6 列（不把卡片压成缩略图）', () {
      expect(cardGridMetrics(4000).columns, kCardGridMaxColumns);
    });

    test('宽度未知时退回最小列数（不把 0/NaN 传进布局层）', () {
      for (final double bad in <double>[0, -10, double.infinity, double.nan]) {
        final CardGridMetrics m = cardGridMetrics(bad);
        expect(m.columns, kCardGridMinColumns, reason: '宽度 = $bad');
        expect(m.cellWidth.isFinite, isTrue);
        expect(m.cellHeight.isFinite, isTrue);
      }
    });

    test('调用方可覆盖最小列宽（搜索页用 220）', () {
      expect(
        cardGridMetrics(600, minColumnWidth: 220).columns,
        2,
        reason: '600 放不下 3 个 220',
      );
    });
  });

  group('格子尺寸', () {
    test('单格宽扣掉列间距', () {
      const double width = 600;
      final CardGridMetrics m = cardGridMetrics(width);
      final double expected = (width - kCardGridSpacing * (m.columns - 1)) / m.columns;
      expect(m.cellWidth, closeTo(expected, 0.01));
    });

    test('格子高 = 3:4 封面 + 文字区', () {
      final CardGridMetrics m = cardGridMetrics(600);
      expect(
        m.cellHeight,
        closeTo(m.cellWidth * 4 / 3 + kCardGridCaptionHeight, 0.01),
      );
      expect(m.cellHeight, greaterThan(m.cellWidth), reason: '封面是竖构图');
    });

    test('childAspectRatio 与宽高自洽（可直接喂给 SliverGridDelegate）', () {
      final CardGridMetrics m = cardGridMetrics(900);
      expect(
        m.childAspectRatio,
        closeTo(m.cellWidth / m.cellHeight, 1e-9),
      );
    });

    test('同一宽度重复调用结果稳定（纯函数）', () {
      final CardGridMetrics a = cardGridMetrics(777);
      final CardGridMetrics b = cardGridMetrics(777);
      expect(a.columns, b.columns);
      expect(a.cellWidth, b.cellWidth);
      expect(a.cellHeight, b.cellHeight);
    });
  });

  group('与尺寸令牌的关系', () {
    test('默认间距就是 AppSpacing.md', () {
      expect(kCardGridSpacing, AppSpacing.md);
    });
  });
}
