import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/image_gen_detail_page.dart';

/// App 生图详情页（对齐网页版 `image_gen/log_detail.html`）。
///
/// 以前 App 的「详情」只是个图片查看器：没有状态/尺寸/张数/模型/消耗点数/生成时间，
/// 没有参考图，没有复制提示词，没有「同款生成」，失败原因也看不到；而且没有产图的
/// 记录连点都点不开（`_openLog` 里 `if (images.isEmpty) return;`）。这里把补齐后的
/// 内容逐项钉住。
///
/// 注意：页面里的图片走**认证网络加载**，widget 测试里必然失败 —— 用
/// `tester.takeException()` 收掉那个异常（页面本身有 errorBuilder，不会崩），
/// 断言只针对文字内容。
void main() {
  Map<String, dynamic> logOf({
    String status = 'success',
    String error = '',
    int count = 1,
    List<String> images = const <String>[
      'https://example.invalid/v1/image-gen/output/1/0',
    ],
    List<String> refs = const <String>[],
  }) {
    return <String, dynamic>{
      'id': 7,
      'first_image': images.isEmpty ? '' : images.first,
      'images': images,
      'references': refs,
      'prompt': '一只在窗边的猫',
      'model_name': 'G Imagine',
      'size': '1024x1024',
      'count': count,
      'points_spent': '3.5',
      'status': status,
      'error': error,
      'created_at': '2026-10-04 15:12',
    };
  }

  /// 把测试视口调高：详情页第一屏是主图（1:1），默认 800×600 的窗口会把下面的
  /// 状态/参数/提示词全部挤出可视区 —— 而 ListView 是懒加载的，屏幕外的内容**根本不在
  /// widget 树里**，find.text 自然找不到。这里给一个高视口，让整页都渲染出来。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpDetail(WidgetTester tester, Map<String, dynamic> log) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(home: ImageGenDetailPage(log: log)),
    );
    await tester.pump();
    tester.takeException(); // 图片加载失败（测试环境无网络），页面已用 errorBuilder 兜住
  }

  testWidgets('成功记录：状态/尺寸/张数/模型/消耗/时间/提示词 都在', (WidgetTester tester) async {
    await pumpDetail(tester, logOf());

    expect(find.text('生图作品详情'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('尺寸 1024x1024'), findsOneWidget);
    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('模型 G Imagine'), findsOneWidget);
    expect(find.text('消耗 3.5 点'), findsOneWidget);
    expect(find.text('2026-10-04 15:12'), findsOneWidget);
    expect(find.text('提示词 Prompt'), findsOneWidget);
    expect(find.text('一只在窗边的猫'), findsOneWidget);
    // 底部操作栏
    expect(find.text('下载原图'), findsOneWidget);
    expect(find.text('同款生成'), findsOneWidget);
  });

  testWidgets('参考图：显示张数（点开可放大）', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      logOf(refs: const <String>[
        'https://example.invalid/v1/image-gen/reference/1/0',
        'https://example.invalid/v1/image-gen/reference/1/1',
      ]),
    );
    expect(find.text('所用参考图（2 张）'), findsOneWidget);
  });

  testWidgets('没有参考图时不显示参考图区块', (WidgetTester tester) async {
    await pumpDetail(tester, logOf());
    expect(find.textContaining('所用参考图'), findsNothing);
  });

  testWidgets('复制提示词：真的写进剪贴板并给出提示', (WidgetTester tester) async {
    await pumpDetail(tester, logOf());

    // widget 测试里没有真实剪贴板通道：不 mock 的话 Clipboard.setData 会抛
    // MissingPluginException，提示也就弹不出来。这里既提供实现，又把内容截下来断言。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.tap(find.text('复制'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, '一只在窗边的猫');
    expect(find.text('已复制提示词'), findsOneWidget);
  });

  testWidgets('同款生成：把提示词 pop 回工作台', (WidgetTester tester) async {
    useTallViewport(tester);
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(ctx).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => ImageGenDetailPage(log: logOf()),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException();

    await tester.tap(find.text('同款生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(popped, '一只在窗边的猫');
  });

  testWidgets('失败记录：显示失败原因与占位，且不能下载', (WidgetTester tester) async {
    await pumpDetail(
      tester,
      logOf(
        status: 'failed',
        error: '生图接口错误 (400): Invalid request: multipart: NextPart: EOF',
        images: const <String>[],
      ),
    );

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('本次未产出图像'), findsOneWidget);
    expect(find.textContaining('multipart: NextPart: EOF'), findsOneWidget);
    // 没有图时「下载原图」按钮禁用
    final OutlinedButton download = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '下载原图'),
    );
    expect(download.onPressed, isNull, reason: '没有产出图时下载按钮应禁用');
  });

  testWidgets('部分完成：状态文案与失败区分开', (WidgetTester tester) async {
    await pumpDetail(tester, logOf(status: 'partial', count: 2, images: const <String>[
      'https://example.invalid/v1/image-gen/output/1/0',
    ]));
    expect(find.text('部分完成'), findsOneWidget);
    expect(find.text('失败'), findsNothing);
  });
}
