import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `FitText`的「短文本缩放下限」（minShrink）契约。
///
///背景：6字以内的文本会被套 FittedBox强制单行，空间不足时**无限缩小**。
///字号调大后，固定宽度容器里的短标签就「长到装不下为止」——看起来像字号
///没生效。minShrink给出一个下限：缩得太狠就宁可不缩、允许换行。
///
///关键约束：**默认值0必须与历史行为完全一致**（无条件缩到装下为止），
///否则全项目750余处 FitText的观感会一起变。
const TextStyle kStyle = TextStyle(fontSize:14);

Widget _host(double width, Widget child) => MaterialApp(
 home: Scaffold(
 body: Align(
 alignment: Alignment.topLeft,
 child: SizedBox(width: width, child: child),
 ),
 ),
 );

void main() {
 testWidgets('默认（minShrink=0）：窄容器里仍然缩字保单行', (WidgetTester tester) async {
 await tester.pumpWidget(_host(40, const FitText('测试四个字', style: kStyle)));
 await tester.pump();

 expect(find.byType(FittedBox), findsOneWidget);
 final double h = tester.getSize(find.byType(FittedBox)).height;
 //单行高度：14 ×1.x ——明显小于两行。
 expect(h, lessThan(14 *2));
 });

 testWidgets('minShrink=0.9：缩得太狠时改为不缩、允许换行', (WidgetTester tester) async {
 await tester.pumpWidget(
 _host(40, const FitText('测试四个字', style: kStyle, minShrink:0.9)),
 );
 await tester.pump();

 expect(find.byType(FittedBox), findsNothing, reason: '不能再压字');
 final double h = tester.getSize(find.byType(Text).first).height;
 expect(h, greaterThan(14 *1.4), reason: '应换成多行，而不是压成一行小字');
 });

 testWidgets('minShrink=0.9：宽容器里照旧走 FittedBox（不破坏单行保证）', (WidgetTester tester) async {
 await tester.pumpWidget(
 _host(400, const FitText('测试四个字', style: kStyle, minShrink:0.9)),
 );
 await tester.pump();

 expect(find.byType(FittedBox), findsOneWidget);
 });

 testWidgets('没有指定 minShrink的既有调用完全不受影响', (WidgetTester tester) async {
 await tester.pumpWidget(_host(400, const FitText('完成', style: kStyle)));
 await tester.pump();
 expect(find.byType(FittedBox), findsOneWidget);
 });
}
