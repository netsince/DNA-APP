import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各栏目页的颜色(页面级 ColoredBox,查找与几何断言用)。
Color pageColor(int i) => Color(0xFF000000 | (0x111111 * (i + 1)));

/// 构造一个可驱动的飞行宿主:6 个假栏目页,
/// 用 AnimationController 手动推进进度,断言各阶段视口里是谁。
///
/// 方向约定(与实现一致):胶片向负方向滑——旧页从上/左退出,
/// 新页从下/右进入(标准"下一页"走向)。
Future<AnimationController> pumpFlight(
  WidgetTester tester, {
  Axis axis = Axis.vertical,
  int fromIndex = 0,
  int toIndex = 3,
}) async {
  final AnimationController controller = AnimationController(
    vsync: tester,
    duration: sectionTravelDuration((toIndex - fromIndex).abs()),
  );
  const List<AppSection> sections = AppSection.values;
  final List<Widget> pages = <Widget>[
    for (int i = 0; i < sections.length; i++)
      ColoredBox(
        color: pageColor(i),
        child: Center(child: Text('栏目$i')),
      ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext ctx, _) => AppSectionSwitcher.buildFlight(
          context: ctx,
          animation: controller,
          axis: axis,
          fromIndex: fromIndex,
          toIndex: toIndex,
          sections: sections,
          pages: pages,
          child: pages[toIndex],
        ),
      ),
    ),
  );
  return controller;
}

Finder pageAt(int i) => find.byWidgetPredicate(
      (Widget w) => w is ColoredBox && w.color == pageColor(i),
    );

void main() {
  testWidgets('纵向飞行 首页(0)→世界(3):途经页逐个掠过,远端页不挂载',
      (WidgetTester tester) async {
    final AnimationController controller =
        await pumpFlight(tester, fromIndex: 0, toIndex: 3);

    // t=0:只有起点页在场。
    controller.value = 0;
    await tester.pump();
    expect(pageAt(0), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(3), findsNothing);

    // t=0.15 → 缓动约 0.40 → 已滑约 1.2 步:
    // 起点页出局(-1.2),栏目1(-0.2)与栏目2(+0.8)在场,
    // 目标页栏目3(+1.8)尚未挂载。
    controller.value = 0.15;
    await tester.pump();
    expect(pageAt(0), findsNothing);
    expect(pageAt(1), findsOneWidget);
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsNothing);

    // t=0.5 → 缓动约 0.88 → 已滑约 2.6 步:
    // 栏目2(-0.6)与目标页(+0.4)在场,栏目1 已出局,
    // 栏目4(+1.4)永不出场。
    controller.value = 0.5;
    await tester.pump();
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(4), findsNothing);

    // t=1:只剩目标页。
    controller.value = 1;
    await tester.pump();
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(0), findsNothing);
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsNothing);
    controller.dispose();
  });

  testWidgets('横向飞行 群聊(1)→世界(3):掠过我家(2),不经过主页(0)',
      (WidgetTester tester) async {
    final AnimationController controller = await pumpFlight(
      tester,
      axis: Axis.horizontal,
      fromIndex: 1,
      toIndex: 3,
    );

    // t=0.5 → 已滑约 2.6 步:我家(-0.6)在视口掠过,
    // 世界(+0.4)进入中;主页(-1.6 反方向)与世界之外无任何页。
    controller.value = 0.5;
    await tester.pump();
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(0), findsNothing);

    controller.value = 1;
    await tester.pump();
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsNothing);
    controller.dispose();
  });

  testWidgets('偏移几何:位移 = -缓动进度 × 视口,方向为负,无交叉轴分量',
      (WidgetTester tester) async {
    AnimationController controller = await pumpFlight(
      tester,
      axis: Axis.horizontal,
      fromIndex: 0,
      toIndex: 1,
    );
    // 任意原始进度:起点页向左退出 -eased×w,目标页从右侧
    // (1-eased)×w 处趋近。视口宽取页面实例自身的宽
    // (Positioned 强制其等于视口)。
    const double raw = 0.09;
    controller.value = raw;
    await tester.pump();
    final Rect p0 = tester.getRect(pageAt(0));
    final Rect p1 = tester.getRect(pageAt(1));
    final double eased = AppMotion.travel.transform(raw);
    expect(p0.left, closeTo(-eased * p0.width, 0.5));
    expect(p1.left, closeTo((1 - eased) * p1.width, 0.5));
    expect(p0.top, 0); // 横向飞行:无纵向分量
    expect(p0.left, lessThan(0)); // 方向:旧页向左退出
    expect(p1.left, greaterThan(0)); // 目标页从右侧趋近
    controller.dispose();

    controller = await pumpFlight(
      tester,
      axis: Axis.vertical,
      fromIndex: 0,
      toIndex: 1,
    );
    controller.value = raw;
    await tester.pump();
    final Rect v0 = tester.getRect(pageAt(0));
    final Rect v1 = tester.getRect(pageAt(1));
    final double easedV = AppMotion.travel.transform(raw);
    expect(v0.top, closeTo(-easedV * v0.height, 0.5));
    expect(v1.top, closeTo((1 - easedV) * v1.height, 0.5));
    expect(v0.left, 0); // 纵向飞行:无横向分量
    expect(v0.top, lessThan(0)); // 方向:旧页向上退出
    expect(v1.top, greaterThan(0)); // 目标页从底侧趋近
    controller.dispose();
  });

  testWidgets('时长随距离递增且封顶', (WidgetTester tester) async {
    expect(sectionTravelDuration(1), AppMotion.sectionTravel);
    expect(sectionTravelDuration(2), const Duration(milliseconds: 390));
    expect(sectionTravelDuration(3), const Duration(milliseconds: 480));
    expect(sectionTravelDuration(10), AppMotion.sectionTravelCap);
  });
}
