import 'package:dna/island_app/recommend_page.dart';
import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

///站长推荐页的排布契约。
///
///##原来的问题
///
///`constraints.maxWidth <760`直接走单列——手机竖屏永远单列，一张3:4封面的
///卡片横跨整屏、又高又大（用户说的「一张卡占满很大屏幕」）。
///
///##现在的行为
///
///手机竖屏**双列**瀑布流；桌面按宽度自然增加列数（最多6列）。
///创作者卡（横条布局）在窄列下换成头像在上的竖排。
void main() {
 Map<String, dynamic> card(String id) => <String, dynamic>{
 'id': id,
 'name': '角色$id',
 'intro': '简介$id',
 'covers': <String, dynamic>{},
 'author': <String, dynamic>{'username': '作者$id'},
 'view_count':1,
 'copy_count':1,
 };

 Map<String, dynamic> user(String id) => <String, dynamic>{
 'username': '创作者$id',
 'avatar': '',
 'card_count':3,
 };

 Future<void> pump(
 WidgetTester tester,
 Size size,
 List<Map<String, dynamic>> items,
 ) async {
 tester.view.physicalSize = size;
 tester.view.devicePixelRatio =1.0;
 addTearDown(tester.view.reset);
 await tester.pumpWidget(
 MaterialApp(home: RecommendPage(loader: () async => (items: items))),
 );
 await tester.pump();
 await tester.pump();
 }

 List<Map<String, dynamic>> cards(int n) => <Map<String, dynamic>>[
 for (int i =1; i <= n; i++)
 <String, dynamic>{'kind': 'card', 'data': card('$i'), 'note': ''},
 ];

 ///量第一张卡片的宽度。注意：推荐卡片直接用 CardTile（不是 Card）。
 double cardWidth(WidgetTester tester) =>
 tester.getSize(find.byType(CardTile).first).width;

 ///实际列数：把每张卡片左上角 x坐标去重（同一列 x相同）。
 int columnCount(WidgetTester tester) {
 final Set<double> xs = <double>{};
 for (final Element e in find.byType(CardTile).evaluate()) {
 final RenderBox box = e.renderObject! as RenderBox;
 xs.add(box.localToGlobal(Offset.zero).dx.roundToDouble());
 }
 return xs.length;
 }

 testWidgets('手机竖屏（390）：双列，卡片不再横跨整屏', (WidgetTester tester) async {
 await pump(tester, const Size(390,844), cards(4));
 expect(columnCount(tester),2, reason: '手机竖屏就该是双列');
 final double w = cardWidth(tester);
 expect(w, lessThan(390 *0.6), reason: '双列时每张卡应远窄于整屏');
 expect(w, greaterThan(120), reason: '也不能窄到看不清封面');
 });

 testWidgets('平板（820）：列数随宽度增加', (WidgetTester tester) async {
 await pump(tester, const Size(820,1180), cards(8));
 expect(columnCount(tester), greaterThanOrEqualTo(3));
 });

 testWidgets('桌面（1600）：排到4列以上', (WidgetTester tester) async {
 await pump(tester, const Size(1600,900), cards(10));
 expect(columnCount(tester), greaterThanOrEqualTo(4));
 });

 testWidgets('创作者卡在窄列下不溢出', (WidgetTester tester) async {
 await pump(tester, const Size(390,844), <Map<String, dynamic>>[
 <String, dynamic>{
 'kind': 'user',
 'data': user('A'),
 'note': '这是一段比较长的站长推荐语，用来检查窄列下的换行',
 'card_count':3,
 },
 <String, dynamic>{'kind': 'card', 'data': card('1'), 'note': ''},
 ]);
 expect(tester.takeException(), isNull, reason: '窄列不应出现溢出');
 expect(find.textContaining('创作者A'), findsWidgets);
 });
}
