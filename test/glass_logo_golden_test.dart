import 'package:dna/pages/splash/glass_logo_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃动画的观感截图（三个时刻：刚长开 / 定版前 / 第二滴）。
///
/// 跑法：flutter test --update-goldens test/glass_logo_golden_test.dart
void main() {
  for (final double at in <double>[0.45, 0.95, 1.55]) {
    testWidgets('液态玻璃 t=$at', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Container(
            color: const Color(0xFF1A1A1A),
            alignment: Alignment.center,
            child: GlassLogoAnimation(durationMs: 1800, onComplete: () {}),
          ),
        ),
      );
      await tester.pump(); // 让纹理/程序就绪
      await tester.pump(Duration(milliseconds: (at * 1000).round()));
      await expectLater(
        find.byType(GlassLogoAnimation),
        matchesGoldenFile(
          'goldens/glass_logo_${(at * 100).round()}.png',
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  }
}
