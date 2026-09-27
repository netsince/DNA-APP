import 'package:flutter_test/flutter_test.dart';
import 'package:dna/theme/tokens.dart';

void main() {
  group('字号阶令牌', () {
    test('六档字号严格递增且无断层', () {
      const List<double> scale = <double>[
        AppFontSize.tiny,
        AppFontSize.caption,
        AppFontSize.body,
        AppFontSize.subtitle,
        AppFontSize.title,
        AppFontSize.headline,
      ];
      expect(scale, <double>[11, 12, 14, 16, 20, 24]);
      for (int i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]),
            reason: '第 $i 档应大于前一档');
      }
    });

    test('最大相邻跨度不超过 4px(消除原 16→22 的 6px 断层)', () {
      const List<double> scale = <double>[
        AppFontSize.tiny,
        AppFontSize.caption,
        AppFontSize.body,
        AppFontSize.subtitle,
        AppFontSize.title,
        AppFontSize.headline,
      ];
      for (int i = 1; i < scale.length; i++) {
        expect(scale[i] - scale[i - 1], lessThanOrEqualTo(4),
            reason: '${scale[i - 1]} → ${scale[i]} 跨度过大');
      }
    });
  });

  group('列表密度令牌', () {
    test('AppInsets.tile 垂直为 0,交由 ListTile 按 Material 默认密度决定行高', () {
      expect(AppInsets.tile.top, 0);
      expect(AppInsets.tile.bottom, 0);
      expect(AppInsets.tile.left, AppSpacing.lg);
      expect(AppInsets.tile.right, AppSpacing.lg);
    });
  });
}
