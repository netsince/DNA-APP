import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:dna/services/crop_math.dart';

/// 裁剪比例是**服务端硬约束**：比例不对，发布直接 400。
/// 这里守住两件事：裁剪框比例 == 目标比例；输出像素比例也在容差内。
void main() {
  const List<double> ratios = <double>[1.0, 16 / 9, 9 / 16];
  const List<Size> viewports = <Size>[
    Size(360, 640),
    Size(1280, 720),
    Size(1200, 2400),
    Size(500, 500),
  ];

  double deviation(double actual, double expected) =>
      (actual - expected).abs() / expected;

  test('裁剪框比例等于目标比例（各种视口）', () {
    for (final double ratio in ratios) {
      for (final Size vp in viewports) {
        final Rect rect = computeCropRect(vp, ratio);
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
        expect(
          deviation(rect.width / rect.height, ratio),
          lessThan(0.005),
          reason: '视口 $vp 下 $ratio 的裁剪框比例偏了',
        );
        // 不能超出视口
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(vp.width));
        expect(rect.bottom, lessThanOrEqualTo(vp.height));
      }
    }
  });

  test('自由裁剪铺满可用区域', () {
    final Rect rect = computeCropRect(const Size(1000, 800), null, padding: 16);
    expect(rect.left, 16);
    expect(rect.top, 16);
    expect(rect.width, 1000 - 32);
    expect(rect.height, 800 - 32);
  });

  test('输出像素比例与源矩形一致，且长边受限', () {
    const List<Rect> sources = <Rect>[
      Rect.fromLTWH(0, 0, 3000, 1687.5),
      Rect.fromLTWH(0, 0, 1080, 1920),
      Rect.fromLTWH(0, 0, 900, 900),
      Rect.fromLTWH(0, 0, 50, 900),
    ];
    for (final Rect src in sources) {
      final ({int width, int height}) out = outputSizeFor(src);
      expect(out.width, greaterThanOrEqualTo(1));
      expect(out.height, greaterThanOrEqualTo(1));
      final int longSide =
          out.width > out.height ? out.width : out.height;
      expect(longSide, lessThanOrEqualTo(1600));
      expect(
        deviation(out.width / out.height, src.width / src.height),
        lessThan(0.01),
        reason: '源 ${src.width}x${src.height} 的输出比例跑偏了',
      );
    }
  });

  test('极端窄条不会算成 0 像素', () {
    final ({int width, int height}) out =
        outputSizeFor(const Rect.fromLTWH(0, 0, 1, 5000));
    expect(out.width, greaterThanOrEqualTo(1));
    expect(out.height, greaterThanOrEqualTo(1));
  });
}
