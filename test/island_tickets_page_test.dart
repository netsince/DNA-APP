import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/tickets_page.dart';
import 'package:dna/widgets/state_views.dart';

/// `tickets_page` 的页面级渲染测试（空态 / 有数据 / 底条 / 错误态）。
///
/// 这个文件能存在，是因为给 `ApiClient` 加了一个 `debugJsonHandler` 注入点：
/// 在此之前它是私有构造的单例，fetch 闭包在构造时绑死，社区端页面在测试里
/// 根本到不了「有数据」的状态（详情见 docs/TESTING_CONVENTIONS.md 第 6 条）。
///
/// 同时它也是 `PagedListBody` 接入（PR #14）之后，该页唯一的行为网。
Map<String, dynamic> _page({
  required List<Map<String, dynamic>> items,
  bool hasNext = false,
  int pages = 1,
}) {
  return <String, dynamic>{
    'data': <String, dynamic>{
      'items': items,
      'page': 1,
      'pages': pages,
      'total': items.length,
      'has_next': hasNext,
    },
  };
}

Map<String, dynamic> _ticket(int id, String title) {
  return <String, dynamic>{
    'id': id,
    'status': 'open',
    'title': title,
    'last_message': <String, dynamic>{'content': '最后一条回复'},
    'updated_at': '2026-11-20T10:00:00Z',
  };
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: TicketsPage()));
  // 首屏 loading → 列表/空/错误之间是 AnimatedSwitcher 交叉淡入，
  // 且底条是常驻 spinner，所以用固定时长推帧而不是 pumpAndSettle。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfig.setBaseUrl('https://test.invalid');
    AuthSession.instance.debugSetSession(
      token: 'test-token',
      user: <String, dynamic>{'username': 'tester'},
    );
  });

  tearDown(() {
    ApiClient.debugJsonHandler = null;
    AuthSession.instance.debugSetSession();
  });

  testWidgets('空数据 → 显示「暂无工单」，而不是空白页', (WidgetTester tester) async {
    ApiClient.debugJsonHandler = (String method, Uri uri) async {
      if (uri.path == '/api/v1/tickets') {
        return _page(items: <Map<String, dynamic>>[]);
      }
      return _page(items: <Map<String, dynamic>>[]);
    };

    await _pumpPage(tester);

    expect(find.text('暂无工单'), findsOneWidget);
  });

  testWidgets('有数据 → 每条工单都渲染出标题', (WidgetTester tester) async {
    ApiClient.debugJsonHandler = (String method, Uri uri) async =>
        _page(items: <Map<String, dynamic>>[_ticket(1, '退款申请'), _ticket(2, '账号问题')]);

    await _pumpPage(tester);

    expect(find.text('退款申请'), findsOneWidget);
    expect(find.text('账号问题'), findsOneWidget);
    expect(find.text('暂无工单'), findsNothing);
    // 行之间有线（这页是 ListTile 行，显式传了 Divider）。
    expect(find.byType(Divider), findsWidgets);
  });

  testWidgets('还有下一页 → 底部出现加载条', (WidgetTester tester) async {
    ApiClient.debugJsonHandler = (String method, Uri uri) async =>
        _page(items: <Map<String, dynamic>>[_ticket(1, '退款申请')], hasNext: true, pages: 3);

    await _pumpPage(tester);

    expect(find.text('退款申请'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('请求失败 → 统一错误态 + 重试，不退化成「暂无工单」', (WidgetTester tester) async {
    ApiClient.debugJsonHandler = (String method, Uri uri) async {
      throw Exception('服务器打盹了');
    };

    await _pumpPage(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.text('暂无工单'), findsNothing);
  });
}
