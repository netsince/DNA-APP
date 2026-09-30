import 'dart:convert';

import 'package:dna/island/island_api.dart';
import 'package:dna/island/island_card_page.dart';
import 'package:dna/island/island_feed.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「岛」信息流的契约：拉一页、点进详情、出错可重试。
///
/// 用 [MockClient] 造接口响应，所以不碰网络 —— 但**请求参数是真的**
/// （探索用 page/sort，搜索用 q/page/sort，与岛后端一致）。
class _FakeHive extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}

Finder label(String s) => find.byWidgetPredicate(
  (Widget w) => w is Text && w.data == s && w is! FitText,
);

/// 造一个 UTF-8 的 JSON 响应（中文必须走 bytes，否则会变乱码）。
http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

Map<String, dynamic> _pageBody(List<Map<String, dynamic>> items, {bool hasNext = false}) =>
    <String, dynamic>{
      'data': <String, dynamic>{
        'items': items,
        'page': 1,
        'pages': 1,
        'total': items.length,
        'has_next': hasNext,
      },
    };

void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  Future<void> pumpFeed(
    WidgetTester tester,
    AppController c,
    IslandApi api, {
    String? query,
  }) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IslandFeedBody(controller: c, api: api, query: query),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('探索：渲染卡片（名字 + 作者），请求参数与岛一致', (WidgetTester tester) async {
    final AppController c = await boot();
    final List<Uri> requested = <Uri>[];
    final IslandApi api = IslandApi(
      client: MockClient((http.Request request) async {
        requested.add(request.url);
        return _json(
          _pageBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'name': '爱丽丝',
              'author': <String, dynamic>{'nickname': '星野'},
            },
            <String, dynamic>{'id': 'c2', 'name': '鲍勃'},
          ]),
        );
      }),
    );

    await pumpFeed(tester, c, api);

    expect(label('爱丽丝'), findsOneWidget);
    expect(label('星野'), findsOneWidget);
    expect(label('鲍勃'), findsOneWidget);
    expect(label('到底了'), findsOneWidget, reason: 'has_next=false 时应显示到底了');

    expect(requested.single.path, '/api/v1/cards/explore');
    expect(requested.single.queryParameters['page'], '1');
    expect(requested.single.queryParameters['sort'], 'hot');
    expect(
      requested.single.queryParameters.containsKey('page_size'),
      isFalse,
      reason: '岛后端不认 page_size',
    );
  });

  testWidgets('点卡片进详情页（在那里才能试聊/导入）', (WidgetTester tester) async {
    final AppController c = await boot();
    final IslandApi api = IslandApi(
      client: MockClient(
        (http.Request request) async => _json(
          _pageBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c1',
              'name': '爱丽丝',
              'persona': '冷静。',
              'opening': '「你来了。」',
            },
          ]),
        ),
      ),
    );

    await pumpFeed(tester, c, api);
    await tester.tap(label('爱丽丝'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(IslandCardPage), findsOneWidget);
    expect(label('试聊'), findsOneWidget);
    expect(label('导入到我家'), findsOneWidget);
  });

  testWidgets('搜索模式走搜索接口，参数用 q', (WidgetTester tester) async {
    final AppController c = await boot();
    final List<Uri> requested = <Uri>[];
    final IslandApi api = IslandApi(
      client: MockClient((http.Request request) async {
        requested.add(request.url);
        return _json(
          _pageBody(<Map<String, dynamic>>[
            <String, dynamic>{'id': 'c9', 'name': '卡罗尔'},
          ]),
        );
      }),
    );

    await pumpFeed(tester, c, api, query: '北境');

    expect(label('卡罗尔'), findsOneWidget);
    expect(requested.single.path, '/api/v1/cards/search');
    expect(requested.single.queryParameters['q'], '北境');
    expect(requested.single.queryParameters['sort'], 'relevance');
  });

  testWidgets('接口出错：给出错误与重试，重试成功后恢复', (WidgetTester tester) async {
    final AppController c = await boot();
    int calls = 0;
    final IslandApi api = IslandApi(
      client: MockClient((http.Request request) async {
        calls++;
        if (calls == 1) {
          return _json(<String, dynamic>{'message': '服务器开小差了'}, status: 500);
        }
        return _json(
          _pageBody(<Map<String, dynamic>>[
            <String, dynamic>{'id': 'c1', 'name': '爱丽丝'},
          ]),
        );
      }),
    );

    await pumpFeed(tester, c, api);
    expect(find.textContaining('服务器开小差了'), findsWidgets);
    expect(label('重试'), findsOneWidget);

    await tester.tap(label('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(label('爱丽丝'), findsOneWidget);
  });
}
