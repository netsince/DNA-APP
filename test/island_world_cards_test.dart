import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_publish_page.dart';
import 'package:dna/island_app/widgets/world_card_tile.dart';
import 'package:dna/island_app/worlds_body.dart';
import 'package:dna/models/world.dart';

/// 社区「世界卡」的客户端侧。
///
/// 守三件事：
/// 1. 列表项只有元信息，正文绝不进列表（世界书动辄几百 KB）；
/// 2. 详情页「导入」= 取原文 → 解析 → 交给窄接口落盘；
/// 3. 窄接口不能把 AppController 拖进社区（那边是零状态依赖）。
class _FakeSource implements WorldPublishSource {
  _FakeSource(this.worlds);

  final List<World> worlds;

  @override
  List<World> localWorlds() => worlds;
}

class _FakeSink implements WorldImportSink {
  World? received;

  @override
  Future<String> importWorld(World world) async {
    received = world;
    return world.id;
  }
}

Map<String, dynamic> _itemJson({
  String id = 'w1',
  String name = '幻想大陆',
  int entryCount = 24,
  int bytes = 186368,
  int copies = 12,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'summary': '一个用于测试的世界',
    'entry_count': entryCount,
    'payload_bytes': bytes,
    'copy_count': copies,
    'tags': <String>['奇幻', '测试'],
    'author': <String, dynamic>{'username': 'alice', 'nickname': '爱丽丝'},
    'created_at': '2026-01-02T03:04:05',
  };
}

String _worldText() => jsonEncode(<String, dynamic>{
      'id': 'remote-id-1',
      'name': '幻想大陆',
      'summary': '一个用于测试的世界',
      'description': '详细说明',
      'tags': <String>['奇幻'],
      'forbiddenWords': <String>[],
      'archived': false,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'e1',
          'name': '王都',
          'description': '首都',
          'type': 'noun',
          'keys': <String>['都城'],
        },
        <String, dynamic>{
          'id': 'e2',
          'name': '艾琳',
          'description': '女王',
          'type': 'person',
        },
      ],
    });

void main() {
  group('WorldCardSummary', () {
    test('解析列表项：元信息齐全，不含正文', () {
      final WorldCardSummary w = WorldCardSummary.fromJson(_itemJson());
      expect(w.id, 'w1');
      expect(w.name, '幻想大陆');
      expect(w.entryCount, 24);
      expect(w.copyCount, 12);
      expect(w.tags, <String>['奇幻', '测试']);
      // 后端给的是 nickname 优先。
      expect(w.authorName, '爱丽丝');
      // 列表项没有正文相关的字段。
      expect(w.entryNames, isEmpty);
      expect(w.sampleEntry, isNull);
    });

    test('解析浏览数 / 收藏状态', () {
      final Map<String, dynamic> json = _itemJson();
      json['view_count'] = 42;
      json['favorited'] = true;
      json['favorite_count'] = 7;
      final WorldCardSummary w = WorldCardSummary.fromJson(json);
      expect(w.viewCount, 42);
      expect(w.favorited, isTrue);
      expect(w.favoriteCount, 7);
    });

    test('体积标签人读化', () {
      expect(WorldCardSummary.fromJson(_itemJson(bytes: 512)).sizeLabel, '512 B');
      expect(
        WorldCardSummary.fromJson(_itemJson(bytes: 186368)).sizeLabel,
        '182 KB',
      );
      expect(
        WorldCardSummary.fromJson(_itemJson(bytes: 3 * 1024 * 1024)).sizeLabel,
        '3.0 MB',
      );
      expect(WorldCardSummary.fromJson(_itemJson(bytes: 0)).sizeLabel, '');
    });

    test('列表卡片带词条名快照（不解析正文）', () {
      final Map<String, dynamic> json = _itemJson();
      json['preview_names'] = <String>['王都', '艾琳'];
      final WorldCardSummary w = WorldCardSummary.fromJson(json);
      expect(w.previewNames, <String>['王都', '艾琳']);
      // 快照只是名字，不含正文；详情项才给 entryIndex。
      expect(w.entryIndex, isEmpty);
    });

    test('详情项带词条名与示例，示例原样透传', () {
      final Map<String, dynamic> json = _itemJson();
      json['entry_names'] = <String>['王都', '艾琳'];
      json['sample_entry'] = <String, dynamic>{
        'name': '王都',
        'description': '首都',
        'type': 'noun',
        'keys': <String>['都城'],
      };
      final WorldCardSummary w = WorldCardSummary.fromJson(json);
      expect(w.entryNames, <String>['王都', '艾琳']);
      expect(w.sampleEntry?['name'], '王都');
      // 未知字段也不该被丢掉或被误解（原样透传）。
      expect(w.sampleEntry?['keys'], <String>['都城']);
    });
  });

  group('世界栏目', () {
    testWidgets('列表渲染元信息，不渲染正文', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldsBody(
              loader: (int page, WorldsQuery query) async => <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  _itemJson(),
                  _itemJson(id: 'w2', name: '第二个世界'),
                ],
                'page': 1,
                'pages': 1,
                'total': 2,
                'has_next': false,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('幻想大陆'), findsOneWidget);
      expect(find.text('第二个世界'), findsOneWidget);
      expect(find.text('一个用于测试的世界'), findsNWidgets(2));
      expect(find.text('24 词条 · 182 KB · 复制 12'), findsNWidgets(2));
      // 卡片上的标签带 # 前缀（与网页版一致）
      expect(find.text('#奇幻'), findsNWidgets(2));
      expect(find.text('#测试'), findsNWidgets(2));
    });

    testWidgets('瀑布流：卡片高度随内容变化（不再固定）', (WidgetTester tester) async {
      final Map<String, dynamic> longItem = _itemJson(id: 'w1', name: '长简介');
      longItem['summary'] =
          '这是一段很长的简介，用来验证瀑布流里卡片会跟着内容长高，而不是被固定高度裁掉。'
          '再补一句让它稳定地折到两行以上，避免因为字体测量差异恰好只占一行。';
      final Map<String, dynamic> shortItem = _itemJson(id: 'w2', name: '短简介');
      shortItem['summary'] = '短';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldsBody(
              loader: (int page, WorldsQuery query) async => <String, dynamic>{
                'items': <Map<String, dynamic>>[longItem, shortItem],
                'has_next': false,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder tiles = find.byType(WorldCardTile);
      expect(tiles, findsNWidgets(2));
      final double h1 = tester.getSize(tiles.at(0)).height;
      final double h2 = tester.getSize(tiles.at(1)).height;
      expect(h1, isNot(equals(h2)),
          reason: '卡片高度应随内容变化（瀑布流），不该是固定高度');
    });

    testWidgets('空列表给空状态', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldsBody(
              loader: (int page, WorldsQuery query) async => <String, dynamic>{
                'items': <Map<String, dynamic>>[],
                'has_next': false,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有人发布世界卡'), findsOneWidget);
    });

    testWidgets('加载失败给错误态', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldsBody(
              loader: (int page, WorldsQuery query) async =>
                  throw Exception('boom'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('世界列表加载失败，下拉重试'), findsOneWidget);
    });
  });

  group('导入', () {
    testWidgets('取原文 → 解析 → 交给窄接口', (WidgetTester tester) async {
      final _FakeSink sink = _FakeSink();
      await tester.pumpWidget(
        MaterialApp(
          home: WorldDetailPage(
            id: 'w1',
            importSink: sink,
            detailLoader: (String id) async => <String, dynamic>{
              ..._itemJson(),
              'entry_names': <String>['王都', '艾琳'],
              'sample_entry': <String, dynamic>{
                'name': '王都',
                'description': '首都',
                'type': 'noun',
              },
            },
            textDownloader: (String id) async => _worldText(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 详情页只给词条名 + 一条示例，不给全文。
      expect(find.text('包含的词条'), findsOneWidget);
      expect(find.text('王都'), findsWidgets);
      expect(find.text('示例词条'), findsOneWidget);

      await tester.tap(find.text('导入到我的世界'));
      await tester.pumpAndSettle();

      expect(sink.received, isNotNull);
      expect(sink.received!.name, '幻想大陆');
      expect(sink.received!.entries.length, 2);
      expect(sink.received!.entries.first.name, '王都');
    });

    testWidgets('没有窄接口时导入按钮不可点', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorldDetailPage(
            id: 'w1',
            detailLoader: (String id) async => _itemJson(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导入到我的世界'),
      );
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('举报走 type=world', (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 't',
      user: <String, dynamic>{'username': 'alice'},
    );
    addTearDown(() => AuthSession.instance.debugSetSession());

    String? gotType;
    String? gotId;
    String? gotReason;
    await tester.pumpWidget(
      MaterialApp(
        home: WorldDetailPage(
          id: 'w1',
          detailLoader: (String _) async => _itemJson(),
          reasonsLoader: () async => <({String key, String label})>[
            (key: 'spam', label: '垃圾广告 / 刷屏'),
            (key: 'porn', label: '色情低俗'),
          ],
          reportSubmitter: ({
            required String type,
            required String id,
            required String reason,
            String? detail,
          }) async {
            gotType = type;
            gotId = id;
            gotReason = reason;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 举报收在顶栏「更多」菜单里（与角色卡详情的分享菜单同一个位置）。
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('垃圾广告 / 刷屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交举报'));
    await tester.pumpAndSettle();

    // 举报目标类型必须是 world —— 后端 REPORT_TARGETS 里加了它。
    expect(gotType, 'world');
    expect(gotId, 'w1');
    expect(gotReason, 'spam');
  });

  group('发布', () {
    World sample() => World(
          id: 'local-1',
          name: '幻想大陆',
          summary: '测试用',
          description: '',
          tags: const <String>['奇幻'],
          forbiddenWords: const <String>[],
          entries: const <WorldEntry>[],
        );

    testWidgets('发布走完整编辑器，发出去的是裸 World JSON（name 在顶层）',
        (WidgetTester tester) async {
      String? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: WorldPublishPage(
            source: _FakeSource(<World>[sample()]),
            publisher: (String raw) async {
              sent = raw;
              return <String, dynamic>{'id': 'remote-1', 'reused': false};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('幻想大陆'), findsOneWidget);

      // 点行 → 打开完整世界观编辑器（不是「点一下直接发」）
      await tester.tap(find.text('幻想大陆'));
      await tester.pumpAndSettle();
      // FitText 内部会渲染不止一个 Text，所以这里用 findsWidgets。
      expect(find.text('动态词条库'), findsWidgets);
      expect(sent, isNull);

      // 编辑器右上角的保存 = 发布（文案就是「发布到社区」，不是「保存世界」）
      expect(find.text('发布到社区'), findsWidgets);
      await tester.tap(find.text('发布到社区').first);
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(sent!) as Map<String, dynamic>;
      // 裸 World JSON：服务端只读顶层字段，套一层 world:{...} 它就读不到。
      expect(decoded['name'], '幻想大陆');
      expect(decoded.containsKey('world'), isFalse);
    });

    testWidgets('从 JSON 识别：贴进去直接进编辑器', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorldPublishPage(
            source: _FakeSource(<World>[]),
            publisher: (String raw) async =>
                <String, dynamic>{'id': 'remote-1', 'reused': false},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('从 JSON 识别'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        jsonEncode(<String, dynamic>{
          'name': '导入世界',
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'e1', 'name': '王都', 'description': '首都'},
          ],
        }),
      );
      await tester.tap(find.text('识别并继续'));
      await tester.pumpAndSettle();

      // 直接进编辑器，名称已填好
      expect(find.text('动态词条库'), findsWidgets);
      expect(find.text('导入世界'), findsWidgets);
    });

    testWidgets('没有本地世界时给空状态', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WorldPublishPage(source: _FakeSource(<World>[]))),
      );
      await tester.pumpAndSettle();
      expect(find.text('你还没有创建过世界，先在「世界」里建一个吧'), findsOneWidget);
    });

    testWidgets('没有来源时给提示', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: WorldPublishPage()));
      await tester.pumpAndSettle();
      expect(find.text('当前环境没有可读取的本地世界'), findsOneWidget);
    });
  });

  test('本体编辑器不得在打开时请求社区接口', () {
    // 热门标签是社区的东西。本体编辑器一打开就去请求社区接口，既破坏本体
    // 离线可用的前提，也不受「关闭社区」开关的约束 —— 候选必须由调用方注入。
    for (final String f in <String>[
      'lib/pages/world_editor_page.dart',
      'lib/pages/ta_editor_page.dart',
    ]) {
      final String src = File(f).readAsStringSync();
      expect(src.contains('getWorldTags'), isFalse,
          reason: '$f 不该拉社区热门标签');
      expect(src.contains('getExploreMeta'), isFalse,
          reason: '$f 不该拉社区热门标签');
    }
    // 角色卡本体编辑器连社区客户端都不该 import。
    final String taSrc =
        File('lib/pages/ta_editor_page.dart').readAsStringSync();
    final RegExp clientImport =
        RegExp(r'^import\s+.*island_app/api/client.*;', multiLine: true);
    expect(clientImport.hasMatch(taSrc), isFalse,
        reason: '角色卡本体编辑器不该依赖社区 API 客户端');
  });

  test('导入窄接口不能把 AppController 拖进社区', () {
    // 社区对主应用是零状态依赖（只 import 两个 widget）。为了一个「导入世界」
    // 的功能把整个 AppController 传进去，这条边界就废了 —— 所以只认一个方法。
    final String src =
        File('lib/island_app/world_import_sink.dart').readAsStringSync();
    // 只看 import 行 —— 文档里提到 AppController 是在解释「为什么不传它」。
    final RegExp forbidden = RegExp(
      r'^import\s+.*(app_controller|dna/state/).*;',
      multiLine: true,
    );
    expect(forbidden.hasMatch(src), isFalse,
        reason: '窄接口只该依赖 World 模型，不该 import AppController / state');
    expect(src.contains('abstract interface class WorldImportSink'), isTrue);
  });
}
