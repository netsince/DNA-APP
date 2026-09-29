import 'package:dna/widgets/app_section.dart';
import 'package:dna/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 转场动画与页面构建解耦:fadeThroughBuilder 是纯函数,
  // 用 AnimationController 直接驱动,验证三阶段行为,
  // 无需构造 AppController(页面构建由各页面渲染测试覆盖)。
  testWidgets('阶段一(t<0.35):背景信封盖住旧页;新页未出现',
      (WidgetTester tester) async {
    final AnimationController controller = AnimationController(
      vsync: tester,
      duration: AppMotion.section,
    );
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            captured = context;
            return AnimatedBuilder(
              animation: controller,
              builder: (BuildContext ctx, _) =>
                  AppSectionSwitcher.fadeThroughBuilder(
                ctx,
                controller,
                controller,
                const Text('新页'),
              ),
            );
          },
        ),
      ),
    );
    final Color surface = Theme.of(captured).colorScheme.surface;
    // 信封 = surface.withValues(alpha: 随进度变化);忽略 alpha 比 RGB。
    bool isEnvelope(Widget w) =>
        w is ColoredBox && w.color.withValues(alpha: 1.0) == surface;
    final Finder envelope = find.byWidgetPredicate(isEnvelope);

    // t=0:信封全透明 —— 旧页(蓝色)可见,新页尚未挂出。
    controller.value = 0;
    await tester.pump();
    expect(find.text('新页'), findsNothing);

    // t=0.17(阶段一中点):信封不透明度 > 0,正在盖住旧页。
    controller.value = 0.17;
    await tester.pump();
    expect(envelope, findsOneWidget);

    // t=0.5(阶段二):新页淡入出现,信封不再存在。
    controller.value = 0.5;
    await tester.pump();
    expect(find.text('新页'), findsOneWidget);
    expect(envelope, findsNothing);

    // t=1:转场完成,新页常驻。
    controller.value = 1.0;
    await tester.pump();
    expect(find.text('新页'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('令牌接线:时长 250ms、分界 0.30/0.35',
      (WidgetTester tester) async {
    expect(AppMotion.section, const Duration(milliseconds: 250));
    expect(AppMotion.fadeOutEnd, 0.30);
    expect(AppMotion.fadeInStart, 0.35);
  });
}
