import 'package:dna/pages/splash/glass_logo_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃动画的观感截图（三个时刻：刚长开 / 定版前 / 第二滴）。
///
/// 跑法：flutter test --update-goldens test/glass_logo_golden_test.dart
void main() {
  setUp(() => GlassLogoAnimation.debugSkipFirstFrameGate = true);
  tearDown(() => GlassLogoAnimation.debugSkipFirstFrameGate = false);

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
      // 资源解码是真实异步 I/O，widget 测试里要用 runAsync 放行。
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      // 时钟按「每帧最多 50ms」累加，所以必须小步推进；一次 pump 大跨度只能走 50ms。
      await tester.pump(); // 首帧 → 起钟
      await tester.pump(const Duration(milliseconds: 16)); // 记基准
      for (int i = 0; i < (at / 0.05).round(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
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
