import 'package:dna/widgets/app_responsive_wrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 卡片列表的响应式多列排布契约。
///
/// 桌面宽窗口下单列会把卡片拉得很宽、横向空间全浪费;这里锁定
/// "够宽就并排、窄了回落单列"的行为,避免以后调宽度时退化。
void main() {
  Widget harness({required double width, required double height}) {
    return MaterialApp(
      home: Scaffold(
        body: AppResponsiveWrap(
          itemCount: 6,
          minItemWidth: 340,
          itemBuilder: (BuildContext context, int i) =>
              SizedBox(key: ValueKey<int>(i), height: 100, child: Text('卡片$i')),
        ),
      ),
    );
  }

  testWidgets('宽窗口:按可用宽度并排多列', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(width: 1300, height: 800));

    // 1300 - 左右各 16 = 1268;1268 / 340 = 3.7 ⇒ 3 列(上限 3)。
    final Rect c0 = tester.getRect(find.byKey(const ValueKey<int>(0)));
    final Rect c1 = tester.getRect(find.byKey(const ValueKey<int>(1)));
    final Rect c2 = tester.getRect(find.byKey(const ValueKey<int>(2)));
    final Rect c3 = tester.getRect(find.byKey(const ValueKey<int>(3)));

    // 同一行的三张卡:顶对齐、横向依次排开。
    expect(c1.top, closeTo(c0.top, 0.5));
    expect(c2.top, closeTo(c0.top, 0.5));
    expect(c1.left, greaterThan(c0.left));
    expect(c2.left, greaterThan(c1.left));
    // 第四张换行。
    expect(c3.top, greaterThan(c0.top));
    expect(c3.left, closeTo(c0.left, 0.5));
    // 卡片宽度均分剩余空间,且不小于最小宽度。
    expect(c0.width, greaterThanOrEqualTo(340));
    expect(c1.width, closeTo(c0.width, 0.5));
  });

  testWidgets('窄窗口:回落单列(不留空列)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(width: 400, height: 800));

    // 400 - 32 = 368 < 340×2 ⇒ 单列:纵向依次排列、左缘相同。
    final Rect c0 = tester.getRect(find.byKey(const ValueKey<int>(0)));
    final Rect c1 = tester.getRect(find.byKey(const ValueKey<int>(1)));
    expect(c1.left, closeTo(c0.left, 0.5));
    expect(c1.top, greaterThan(c0.top));
    expect(c0.width, closeTo(368, 0.5));
  });
}
