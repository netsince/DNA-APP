import 'package:dna/theme/font_scale.dart';
import 'package:dna/widgets/animated_font_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 字号切换的过渡动画契约。
///
/// 三件事必须同时成立才叫「过渡」：中间帧真的在两端之间、落地值准确、
/// 以及**静止在「跟随系统」档时不接管**（否则系统非线性字号会被线性近似顶掉）。
void main() {
  final ValueNotifier<TextScaler?> seen = ValueNotifier<TextScaler?>(null);

  tearDown(() => seen.value = null);

  Future<void> mount(
    WidgetTester tester, {
    required ValueNotifier<int> step,
    double systemScale = 1.0,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(systemScale),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: step,
            builder: (BuildContext context, int value, Widget? _) {
              return AnimatedFontScale(
                step: value,
                child: Builder(
                  builder: (BuildContext ctx) {
                    seen.value = MediaQuery.textScalerOf(ctx);
                    return const SizedBox(width: 8, height: 8);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double? factor() => seen.value?.scale(100);

  testWidgets('静止在 0 档：不接管，系统倍率原样透传', (WidgetTester tester) async {
    final ValueNotifier<int> step = ValueNotifier<int>(AppFontScale.followSystem);
    addTearDown(step.dispose);
    await mount(tester, step: step, systemScale: 1.3);
    expect(factor(), closeTo(130, 0.001));
  });

  testWidgets('静止在固定档：就是该档倍率', (WidgetTester tester) async {
    final ValueNotifier<int> step = ValueNotifier<int>(3);
    addTearDown(step.dispose);
    await mount(tester, step: step, systemScale: 1.3);
    expect(factor(), closeTo(AppFontScale.scaleOf(3)! * 100, 0.001));
  });

  testWidgets('3 → 5：中间帧在两端之间，落地等于 5 档', (WidgetTester tester) async {
    final ValueNotifier<int> step = ValueNotifier<int>(3);
    addTearDown(step.dispose);
    await mount(tester, step: step);
    final double from = AppFontScale.scaleOf(3)! * 100;
    final double to = AppFontScale.scaleOf(5)! * 100;

    step.value = 5;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final double? mid = factor();
    expect(mid, isNotNull);
    expect(
      mid! > from && mid < to,
      isTrue,
      reason: '中间帧应在 $from..$to 之间，实际 $mid',
    );

    await tester.pumpAndSettle();
    expect(factor(), closeTo(to, 0.001));
  });

  testWidgets('5 → 0：先滚回系统倍率，落地后交还系统（不再覆盖）', (WidgetTester tester) async {
    final ValueNotifier<int> step = ValueNotifier<int>(5);
    addTearDown(step.dispose);
    await mount(tester, step: step, systemScale: 1.3);
    expect(factor(), closeTo(AppFontScale.scaleOf(5)! * 100, 0.001));

    step.value = AppFontScale.followSystem;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final double? mid = factor();
    expect(mid, isNotNull);
    expect(mid! < AppFontScale.scaleOf(5)! * 100, isTrue,
        reason: '应已经在往回降');

    await tester.pumpAndSettle();
    expect(factor(), closeTo(130, 0.001), reason: '落地必须等于系统值');
  });

  testWidgets('减少动态效果：一帧到位，不做插值', (WidgetTester tester) async {
    final ValueNotifier<int> step = ValueNotifier<int>(3);
    addTearDown(step.dispose);
    await mount(tester, step: step, reduceMotion: true);

    step.value = 5;
    await tester.pump();
    expect(
      factor(),
      closeTo(AppFontScale.scaleOf(5)! * 100, 0.001),
      reason: 'disableAnimations 时必须直接跳终值',
    );
  });
}
