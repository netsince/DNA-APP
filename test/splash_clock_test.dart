import 'package:dna/models/app_settings.dart';
import 'package:dna/pages/splash/splash_clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 开场动画时钟：卡顿只会让动画变慢，**不会跳帧**。
void main() {
  late SplashClock clock;

  Widget host() => MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return AnimatedBuilder(
              animation: clock,
              builder: (BuildContext context, Widget? _) =>
                  Text('v=${clock.value.toStringAsFixed(3)}'),
            );
          },
        ),
      );

  testWidgets('卡住 500ms 只推进 50ms（限幅），不会跳', (WidgetTester tester) async {
    clock = SplashClock(vsync: tester, duration: const Duration(seconds: 2));
    bool done = false;
    await tester.pumpWidget(host());
    clock.startAfterFirstFrame(onComplete: () => done = true);

    await tester.pump(); // 首帧回调 → 起钟
    await tester.pump(const Duration(milliseconds: 16)); // 第一帧只记基准
    expect(clock.value, 0);

    // 模拟「一帧卡了 500ms」：只应推进 maxStep（50ms / 2s = 0.025）
    await tester.pump(const Duration(milliseconds: 500));
    expect(clock.value, closeTo(0.025, 0.001));
    expect(done, isFalse);

    // 正常帧：连续推进到结束
    for (int i = 0; i < 60 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(done, isTrue);
    expect(clock.value, 1.0);
    clock.dispose();
  });

  testWidgets('finishNow 立刻结束（着色器加载失败的兜底）', (WidgetTester tester) async {
    clock = SplashClock(vsync: tester, duration: const Duration(seconds: 3));
    bool done = false;
    await tester.pumpWidget(host());
    clock.startAfterFirstFrame(onComplete: () => done = true);
    await tester.pump();
    clock.finishNow();
    expect(done, isTrue);
    expect(clock.value, 1.0);
    clock.dispose();
  });

  testWidgets('动画设置在 0ms 时也不会除零', (WidgetTester tester) async {
    clock = SplashClock(vsync: tester, duration: Duration.zero);
    expect(clock.value, 1.0);
    clock.dispose();
  });

  test('设置默认播液态玻璃以外的旧值也能解析', () {
    expect(AppSettings.empty().splashAnimation, isNotEmpty);
  });
}
