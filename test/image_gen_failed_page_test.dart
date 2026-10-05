import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/image_gen_failed_page.dart';
import 'package:dna/island_app/utils/auth_image.dart';

/// App 的「生成失败记录」：用户失败后要能看到自己当时填的提示词、选的参数、
/// 传的参考图和失败原因（以前只有一句错误提示，想重试都无从下手）。
///
/// 卡片是公开组件，可以直接 pump；页面本身要先联网取数据，测试里只覆盖它的
/// 无数据/失败状态。
void main() {
  Map<String, dynamic> failedLog() => <String, dynamic>{
        'id': 1060,
        'images': <String>[],
        'first_image': '',
        'references': <String>[
          'https://example.invalid/v1/image-gen/reference/1060/0',
          'https://example.invalid/v1/image-gen/reference/1060/1',
        ],
        'prompt': '一只戴帽子的猫，赛博朋克风格',
        'model_name': 'G Imagine',
        'size': '768x1024',
        'count': 2,
        'points_spent': '0',
        'status': 'failed',
        'error': '生图接口错误 (400): Invalid request: multipart: NextPart: EOF',
        'created_at': '2026-10-04 15:12',
      };

  testWidgets('失败卡片显示提示词/模型/尺寸/张数/消耗/参考图/失败原因', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImageGenFailedCard(log: failedLog())),
      ),
    );
    await tester.pump();
    tester.takeException(); // 参考图走网络加载，测试环境必然失败（有 errorBuilder 兜住）

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('一只戴帽子的猫，赛博朋克风格'), findsOneWidget);
    expect(find.text('模型 G Imagine'), findsOneWidget);
    expect(find.text('768x1024'), findsOneWidget);
    expect(find.text('2 张'), findsOneWidget);
    expect(find.text('消耗 0 点'), findsOneWidget);
    expect(find.text('2026-10-04 15:12'), findsOneWidget);
    expect(find.textContaining('multipart: NextPart: EOF'), findsOneWidget);

    // 参考图两张都要显示出来（URL 由服务端按序号给）。
    // 岛内的图片走自定义 ImageProvider（带认证头），所以看 AuthNetworkImage.url。
    final List<String> urls = <String>[];
    for (final Image img in tester.widgetList<Image>(find.byType(Image))) {
      final ImageProvider provider = img.image;
      if (provider is AuthNetworkImage) urls.add(provider.url);
    }
    expect(urls, contains('https://example.invalid/v1/image-gen/reference/1060/0'));
    expect(urls, contains('https://example.invalid/v1/image-gen/reference/1060/1'));
  });

  testWidgets('没有参考图时不显示缩略图行', (WidgetTester tester) async {
    final Map<String, dynamic> log = failedLog()..['references'] = <String>[];
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImageGenFailedCard(log: log))),
    );
    await tester.pump();
    tester.takeException();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('点卡片会触发回调（用于进入完整详情）', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageGenFailedCard(log: failedLog(), onTap: () => taps++),
        ),
      ),
    );
    await tester.pump();
    tester.takeException();
    await tester.tap(find.byType(ImageGenFailedCard));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('取不到数据时给出错误与重试，而不是空白页', (WidgetTester tester) async {
    // 未配置服务器地址 ⇒ 请求必然失败
    await tester.pumpWidget(const MaterialApp(home: ImageGenFailedPage()));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
