import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/card_publish_page.dart';
import 'package:dna/island_app/server_config.dart';

/// App 编辑角色卡的两处修复（用户反馈「基本上无法使用：图片错误 + 提交不上去」）：
///
/// 1. **既有图片预览**：卡详情接口给的是相对路径 `/card-image/<id>/<slot>`，以前编辑页
///    对这种路径只画一个占位图标（代码注释写着"无法直接预览"），用户看到的就是"图片
///    加载不出来"。现在补上服务器地址直接显示。
/// 2. **详情拉取失败必须拦住提交**：服务端图片是**覆盖式**替换，拉取失败时既有图为空，
///    提交会把这张卡已有的图片全部删掉。现在显示横幅 + 暂停提交，可点重试。
///
/// 服务端那半（把"本卡自己的图片路径"识别为未改动、原样保留）由
/// 服务端 tests/test_card_edit_image_keep.py 守着。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfig.setBaseUrl('https://example.test');
  });

  Map<String, dynamic> prefill() => <String, dynamic>{
        'id': 'card-1',
        'name': '测试卡',
        'gender': '无性',
        'persona': '人设',
        'intro': '简介',
        'opening': '',
        'original_link': '',
        'tags': <String>['标签A'],
        'dialogue_style': <Map<String, String>>[],
        'images': <String, String>{'square': '/card-image/card-1/square'},
      };

  testWidgets('既有图片（相对路径）会补上服务器地址并真的渲染出来', (WidgetTester tester) async {
    // 图片槽在长表单的下方，默认 800×600 视口里 ListView 不会构建它（懒加载），
    // find 自然找不到 —— 给一个高视口让整页都渲染出来。
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: CardPublishPage(prefill: prefill())),
    );
    await tester.pump();

    final Iterable<Image> images = tester.widgetList<Image>(find.byType(Image));
    final List<String> urls = <String>[];
    for (final Image img in images) {
      final ImageProvider provider = img.image;
      if (provider is NetworkImage) urls.add(provider.url);
    }
    expect(
      urls,
      contains('https://example.test/card-image/card-1/square'),
      reason: '既有图必须用「服务器地址 + 相对路径」渲染，而不是只画占位图标',
    );
  });

  testWidgets('编辑模式下详情拉取失败：显示横幅并拦住提交', (WidgetTester tester) async {
    // 未配置服务器地址 ⇒ getCardDetail 必然失败 ⇒ _detailFailed = true
    await ServerConfig.setBaseUrl('');
    await tester.pumpWidget(
      const MaterialApp(home: CardPublishPage(editCardId: 'card-1')),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('原卡片内容加载失败'),
      findsOneWidget,
      reason: '拉取失败必须显式告知，不能静默继续（否则提交会删掉既有图片）',
    );
    expect(find.text('重试'), findsOneWidget);

    // 点提交：应被硬拦住（先于表单校验），而不是继续走提交流程
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.textContaining('为避免误删图片请先重试加载'), findsOneWidget);
  });
}
