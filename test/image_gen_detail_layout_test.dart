import 'package:dna/island_app/image_gen_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

///生图作品详情页的桌面布局契约。
///
///桌面（≥900）必须**左右分栏**：左边看图、右边看信息。
///旧版是单列 +图片按 AspectRatio铺满整宽 ——1920窗口下图片横贯整屏、
///信息被压到下面很远，鼠标用户要滚很久才能看到提示词。
void main() {
 Future<void> pump(WidgetTester tester, Size size) async {
 tester.view.physicalSize = size;
 tester.view.devicePixelRatio =1.0;
 addTearDown(tester.view.reset);

 await tester.pumpWidget(
 MaterialApp(
 home: ImageGenDetailPage(
 log: <String, dynamic>{
 'status': 'succeeded',
 'prompt': '一个少女站在雨后的街道上，霓虹灯倒影',
 'size': '1024x1024',
 'model_name': 'test-model',
 'count':1,
 'points_spent': '2',
 'created_at': '2026-01-0100:00:00',
 //故意不给图：走占位分支，避免测试里发网络请求。
 'images': <String>[],
 'references': <String>[],
 },
 ),
 ),
 );
 await tester.pump();
 }

 testWidgets('桌面宽屏：左右分栏（图片区与信息区并排）', (WidgetTester tester) async {
 await pump(tester, const Size(1600,900));

 //分栏的标志：页面内有一个水平 Row，且中间有竖直分隔线。
 expect(find.byType(VerticalDivider), findsOneWidget,
 reason: '宽屏应左右分栏；单列时不会有竖直分隔线');

 //图片区（左侧）宽度应明显小于整屏——不再是横贯整屏的巨幅图。
 final Finder stage = find.byType(AspectRatio);
 if (stage.evaluate().isNotEmpty) {
 final double w = tester.getSize(stage.first).width;
 expect(w, lessThan(1600 *0.75), reason: '左侧图片区不该占满整屏');
 }
 });

 testWidgets('手机窄屏：仍是单列，不出现分栏分隔线', (WidgetTester tester) async {
 await pump(tester, const Size(390,844));
 expect(find.byType(VerticalDivider), findsNothing,
 reason: '窄屏保持原来的单列上下排布');
 });

 testWidgets('两种宽度下都能看到提示词与操作按钮', (WidgetTester tester) async {
 for (final Size s in <Size>[const Size(1600,900), const Size(390,844)]) {
 await pump(tester, s);
 expect(find.text('保存原图'), findsOneWidget);
 expect(find.text('同款生成'), findsOneWidget);
 }
 });
}
