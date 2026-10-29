import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

///回归：宽窗口下「生图记录」必须能滚到全部内容。
///
///##曾经的 bug
///
///给 `MasonryGridView`加了「按宽度算列数」的 `LayoutBuilder`之后，
///在**嵌进别人滚动体**的场景（工作台的「最近记录」用 `shrinkWrap: true`）
///父级给的是**无界高度**，`LayoutBuilder`把「无限高」原样传下去，
///网格据此算出的内容高度严重偏小 ——外层 `ListView`的总滚动范围跟着变小。
///
///表现就是用户报的：桌面上只能看到前几条、**拉不下去**；窗口缩小反而能滚。
///实测同一份内容（60项）：不加 `LayoutBuilder`可滚4000，错误写法只有1000。
///
///##现在的约束
///
///`shrinkWrap: true`**不许**套 `LayoutBuilder`；只有自己滚动的网格才能用。
void main() {
 const double kItemH =150;
 const int kCount =60;
 const double kHeaderH =400;

 Widget grid({required bool viaLayoutBuilder}) {
 Widget build(double? width) => MasonryGridView.count(
 shrinkWrap: true,
 physics: const NeverScrollableScrollPhysics(),
 crossAxisCount: width == null ?2 : (width ~/240).clamp(2,6),
 itemCount: kCount,
 itemBuilder: (BuildContext ctx, int i) =>
 SizedBox(height: kItemH, child: Text('item$i')),
 );
 return viaLayoutBuilder
 ? LayoutBuilder(
 builder: (BuildContext ctx, BoxConstraints c) => build(c.maxWidth),
 )
 : build(null);
 }

 Future<double> scrollExtent(
 WidgetTester tester, {
 required bool viaLayoutBuilder,
 required Size size,
 }) async {
 tester.view.physicalSize = size;
 tester.view.devicePixelRatio =1.0;
 addTearDown(tester.view.reset);
 final ScrollController outer = ScrollController();
 addTearDown(outer.dispose);
 await tester.pumpWidget(
 MaterialApp(
 home: Scaffold(
 body: ListView(
 controller: outer,
 children: <Widget>[
 SizedBox(height: kHeaderH, child: const Placeholder()),
 grid(viaLayoutBuilder: viaLayoutBuilder),
 ],
 ),
 ),
 ),
 );
 await tester.pump();
 return outer.hasClients ? outer.position.maxScrollExtent : -1;
 }

 testWidgets('反证：shrinkWrap网格套LayoutBuilder会把可滚距离算小', (WidgetTester tester) async {
 final double normal = await scrollExtent(
 tester,
 viaLayoutBuilder: false,
 size: const Size(1600,900),
 );
 final double bugged = await scrollExtent(
 tester,
 viaLayoutBuilder: true,
 size: const Size(1600,900),
 );
 expect(
 bugged,
 lessThan(normal),
 reason: '这正是用户报「拉不下去」的成因，测试把它记录下来',
 );
 expect(bugged *2, lessThan(normal), reason: '差距应是数量级的（实测1000对4000）');
 });

 testWidgets('修复后：宽窗口可滚距离足够覆盖全部条目', (WidgetTester tester) async {
 //这是 `image_gen_body.dart`现在的写法：shrinkWrap时**不用**LayoutBuilder。
 final double fixedWide = await scrollExtent(
 tester,
 viaLayoutBuilder: false,
 size: const Size(1600,900),
 );
 expect(
 fixedWide,
 greaterThan(3000),
 reason: '必须能滚到后面几十张，而不是只看到前面几个',
 );
 });

 testWidgets('窄窗口同样可滚（不因窗口小而失效）', (WidgetTester tester) async {
 final double narrow = await scrollExtent(
 tester,
 viaLayoutBuilder: false,
 size: const Size(390,844),
 );
 expect(narrow, greaterThan(3000));
 });
}
