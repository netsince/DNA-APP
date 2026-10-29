import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/wide_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

///社区页面「桌面适配」的契约。
///
///背景：社区的 `contentMaxWidth`是 `double.infinity`（岛自带外壳、按整窗宽设计），
///主程序的壳不再替它收窄，于是茶馆/文章/公告这些单列页面在桌面上会被拉成一条
///横跨整屏的文字；生图列表则硬编码2列，1920宽时每张图近950px。
///
///这里守住三个纯函数 ——它们的取值决定了所有页面的观感，最容易被随手改坏。
void main() {
  group('版心宽度 WideContent', () {
    test('长文本比网格窄（正文不能跟卡片墙一样宽）', () {
      expect(WideContent.reading.maxWidth, lessThan(WideContent.grid.maxWidth));
    });

    test('取值都在可读区间（不小于640、不大于1080）', () {
      for (final WideContent k in WideContent.values) {
        expect(k.maxWidth, greaterThanOrEqualTo(640));
        expect(k.maxWidth, lessThanOrEqualTo(1080));
      }
    });
  });

  group('两侧留白 wideInset', () {
    test('窗口比版心窄时不留白', () {
      expect(wideInset(600, maxWidth: 760), 0);
    });

    test('正好等于版心时不留白', () {
      expect(wideInset(760, maxWidth: 760), 0);
    });

    test('1920宽 /760版心 =每侧580', () {
      expect(wideInset(1920, maxWidth: 760), 580);
    });

    test('留白是均分的（两侧相加刚好补足差额）', () {
      final double inset = wideInset(1200, maxWidth: 760);
      expect(inset * 2 + 760, 1200);
    });

    test('非法宽度不留白（避免布局奔溃）', () {
      expect(wideInset(double.infinity, maxWidth: 760), 0);
      expect(wideInset(0, maxWidth: 760), 0);
    });
  });

  group('网格列数 gridColumnsFor', () {
    test('手机宽度给最少2列（与旧行为一致）', () {
      expect(gridColumnsFor(360), 2);
      expect(gridColumnsFor(400), 2);
    });

    test('桌面宽度给更多列（不再是硬编码2列）', () {
      expect(gridColumnsFor(1280), greaterThan(2));
      expect(gridColumnsFor(1920), 6);
    });

    test('列数有上限，超宽不会挤出几十列', () {
      expect(gridColumnsFor(5000), 6);
    });

    test('列宽不小于 minColumnWidth（卡片不会被压小）', () {
      for (final double w in <double>[600, 900, 1440, 1920]) {
        final int cols = gridColumnsFor(w);
        expect(w / cols, greaterThanOrEqualTo(240 - 0.001));
      }
    });

    test('非法宽度回落到最少列', () {
      expect(gridColumnsFor(double.infinity), 2);
      expect(gridColumnsFor(0), 2);
    });
  });

  group('WideBody组件', () {
    testWidgets('宽窗口下内容被收窄并居中', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            //用 Column拉伸：WideBody内部是 Center+ConstrainedBox，
            //子组件若无宽度约束会被压成0（渲染成空白，量不到宽度）。
            body: Column(
              children: <Widget>[
                WideBody(
                  kind: WideContent.reading,
                  child: SizedBox(
                    key: const Key('content'),
                    height: 100,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final double w = tester.getSize(find.byKey(const Key('content'))).width;
      expect(w, WideContent.reading.maxWidth);
    });

    testWidgets('窄窗口下铺满，不被收窄', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            //用 Column拉伸：WideBody内部是 Center+ConstrainedBox，
            //子组件若无宽度约束会被压成0（渲染成空白，量不到宽度）。
            body: Column(
              children: <Widget>[
                WideBody(
                  kind: WideContent.reading,
                  child: SizedBox(
                    key: const Key('content'),
                    height: 100,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final double w = tester.getSize(find.byKey(const Key('content'))).width;
      expect(w, 390);
    });
  });

  group('LoadMoreListView的版心（分页列表共用）', () {
    Widget host({
      required double width,
      WideContent? wide = WideContent.list,
    }) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 600,
          child: LoadMoreListView(
            itemCount: 3,
            itemBuilder: (BuildContext c, int i) =>
                SizedBox(key: Key('item$i'), height: 80),
            hasMore: false,
            onLoadMore: () {},
            wide: wide,
          ),
        ),
      ),
    );

    testWidgets('宽屏下列表被收窄到版心宽度（左右留白）', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: 1600));
      await tester.pump();

      final double itemW = tester.getSize(find.byKey(const Key('item0'))).width;
      expect(itemW, lessThan(1600), reason: '不该横跨整屏');
      expect(
        itemW,
        closeTo(WideContent.list.maxWidth, 1),
        reason: '应正好收窄到版心宽度',
      );
    });

    testWidgets('窄屏下铺满（保持手机观感不变）', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: 390));
      await tester.pump();

      final double itemW = tester.getSize(find.byKey(const Key('item0'))).width;
      expect(itemW, 390);
    });

    testWidgets('wide传 null时不收窄（留给必须铺满的列表）', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: 1600, wide: null));
      await tester.pump();

      final double itemW = tester.getSize(find.byKey(const Key('item0'))).width;
      expect(itemW, 1600);
    });
  });
}
