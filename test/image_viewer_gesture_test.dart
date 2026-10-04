import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/widgets/image_viewer.dart';

/// 图片查看器手势：**左右滑动切图不得被「上下滑动退出」影响**。
///
/// ## 用户反馈的 bug 与根因
///
/// 多图预览里左右滑切图时，画面会被退出动作拽着走，严重时图也切不了。
///
/// 根因（读包源码 + 探针确认）：退出原先由 extended_image 的
/// `ExtendedImageSlidePage` + **图片自身的 `ScaleGestureRecognizer`** 驱动 ——
/// 那个识别器**任意方向**都能接管（focalPoint 位移 36px 即接受），而画廊翻页用的是
/// 横向识别器（横向 18px 即接受）。同一根手指上两者抢手势，斜着滑时退出逻辑先赢：
/// 画面被上下拽、翻页被吞。上一轮只把 `slideAxis` 改成 `vertical`，它只能约束
/// "位移只累计 dy"，**抢手势它管不了**，所以没修干净。
///
/// ## 现在的实现（见 lib/island_app/widgets/image_viewer.dart）
///
/// * `enableSlideOutPage: false`：包内 `handleScaleUpdate` 里"把拖拽转成退出页面"
///   的分支要求 `extendedImageSlidePageState != null`，关掉后这条路径整条失效；
/// * 退出改由自带 `_VerticalDismiss` 负责，它的识别器**只接受纵向明显占优
///   （≥ 横向 1.2 倍）的拖拽**，否则拒绝自己、把手势完整让给画廊翻页；
/// * 放大（scale > 1）时也拒绝自己，纵向拖拽归图片平移。
///
/// ## 为什么横向一定赢（生产路径的时序论证）
///
/// 两个识别器的接受阈值：横向翻页 18px（`kTouchSlop`）、图片缩放 36px
/// （`kPanSlop`，看 focalPoint 位移）。横向占优的拖拽满足 |dx| ≥ |dy|，于是
/// focalPoint 位移 = √(dx²+dy²) ≤ √2·|dx|。所以 36px 的 focal 位移至少要
/// |dx| ≥ 25.5px 才可能达到 —— **横向识别器总在 18px 处先接受**，先接受者赢竞技场。
/// 纵向占优的拖拽反之：自带识别器在 |dy| = 18px 时就接受（此时 focal ≈ 18px
/// 远未到 36px），同样先赢。
///
/// ## 测试覆盖的边界（如实说明）
///
/// 下面 3 条用例跑的是「图片未加载」路径 —— 测试环境里网络图加载不了，
/// 图片自身的 `ScaleGestureRecognizer` 因此不存在，**生产路径的"抢手势"竞争
/// 没法在 widget 测试里复现**（试过注入假 HttpClient：`ExtendedImage` 一直停在
/// 加载中，真实异步 I/O 需要 `tester.runAsync`，而手势模拟不能在 runAsync 里做）。
/// 所以上面那段时序论证是生产路径的主要依据；`_isZoomed()`（放大时让位给平移）
/// 同理只能靠真机确认。
void main() {
  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ImageViewerPage.open(
                  ctx,
                  urls: const <String>[
                    'https://example.invalid/a.png',
                    'https://example.invalid/b.png',
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // 不能用 pumpAndSettle：测试环境里网络图永远停在加载态（转圈动画不停），
    // 只能显式推进帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  bool viewerOpen(WidgetTester tester) =>
      find.byType(ImageViewerPage).evaluate().isNotEmpty;

  Finder gallery() => find.byType(ExtendedImageGesturePageView);

  testWidgets('横向 fling：切到下一张，且不退出', (WidgetTester tester) async {
    await openViewer(tester);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.fling(gallery(), const Offset(-300, 0), 1200);
    await settle(tester);

    expect(find.text('2 / 2'), findsOneWidget, reason: '横向滑动应切到第 2 张');
    expect(viewerOpen(tester), isTrue, reason: '横向滑动不得退出查看器');
  });

  testWidgets('斜向但横向占优：拖拽过程中画面不得被纵向带动（用户症状本身）',
      (WidgetTester tester) async {
    await openViewer(tester);
    final double topBefore = tester.getRect(gallery()).top;

    // 模拟真实手指：横向为主、纵向有抖动
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(ImageViewerPage)),
    );
    for (int i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(-40, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.getRect(gallery()).top,
      closeTo(topBefore, 0.5),
      reason: '横向滑动时画面不能被退出逻辑上下拽动',
    );

    await gesture.up();
    await settle(tester);
    expect(viewerOpen(tester), isTrue, reason: '横向占优的滑动不得退出');
  });

  testWidgets('纵向拖拽：跟手位移并退出', (WidgetTester tester) async {
    await openViewer(tester);
    final double topBefore = tester.getRect(gallery()).top;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(ImageViewerPage)),
    );
    for (int i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(2, 30)); // 纵向为主，横向仅 2px 抖动
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.getRect(gallery()).top,
      greaterThan(topBefore + 50),
      reason: '纵向拖拽时画面应跟手位移',
    );

    await gesture.up();
    await settle(tester);
    expect(viewerOpen(tester), isFalse, reason: '下滑应退出');
  });
}
