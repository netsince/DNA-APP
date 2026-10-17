import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/app_drawer.dart';
import 'package:dna/island_app/auth_session.dart';

/// 社区侧边栏的结构。
///
/// 它是**一份内容、两种形态**：竖屏抽屉与横屏常驻左栏共用同一份（横屏没有底栏，
/// 所以这一份就是唯一导航）。所以这里测的是「分组与层次」，不是「形态分叉」。
Finder findText(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w.data == s);

void main() {
  setUp(() => AuthSession.instance.debugSetSession());
  tearDown(() => AuthSession.instance.debugSetSession());

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, height: 800, child: child),
        ),
      );

  AppDrawerContent build({
    VoidCallback? onLogin,
    VoidCallback? onExit,
    VoidCallback? onNotifications,
    VoidCallback? onMyCards,
    VoidCallback? onMyFavorites,
  }) {
    return AppDrawerContent(
      selected: AppNavTarget.recommend,
      onSelect: (_) {},
      onShowAnnouncement: () {},
      onOpenArticles: () {},
      onOpenRecommend: () {},
      onOpenProxy: () {},
      onOpenSponsor: () {},
      onOpenNotifications: onNotifications,
      onOpenMyCards: onMyCards,
      onOpenMyFavorites: onMyFavorites,
      onLogin: onLogin,
      onExitToMainApp: onExit,
    );
  }

  testWidgets('未登录：给出登录引导，且不显示「我的」分组',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(build(onLogin: () {})));
    await tester.pumpAndSettle();

    expect(findText('登录后可发布角色卡、收藏与评论'), findsOneWidget);
    expect(findText('登录'), findsOneWidget);
    // 未登录时整组隐藏，而不是列一堆点了要登录的项。
    expect(findText('我的'), findsNothing);
    expect(findText('通知'), findsNothing);
    // 导航与社区分组照常。
    expect(findText('推荐'), findsOneWidget);
    expect(findText('社区'), findsOneWidget);
  });

  testWidgets('登录后：「我的」分组出现，身份块显示昵称与 @用户名',
      (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 't',
      user: <String, dynamic>{'username': 'alice', 'nickname': '爱丽丝'},
    );
    await tester.pumpWidget(
      host(
        build(
          onNotifications: () {},
          onMyCards: () {},
          onMyFavorites: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(findText('我的'), findsOneWidget);
    expect(findText('通知'), findsOneWidget);
    expect(findText('我的发布'), findsOneWidget);
    expect(findText('我的收藏'), findsOneWidget);
    // 只放三项：低频的留在「我」页，别把侧栏塞成档案柜。
    expect(findText('我点赞的'), findsNothing);
    expect(findText('我的点数'), findsNothing);
    expect(findText('我的工单'), findsNothing);

    expect(findText('爱丽丝'), findsOneWidget);
    expect(findText('@alice'), findsOneWidget);
  });

  testWidgets('身份块与「返回主应用」都不在滚动列表里（吸顶 / 固定底部）',
      (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 't',
      user: <String, dynamic>{'username': 'alice', 'nickname': '爱丽丝'},
    );
    await tester.pumpWidget(host(build(onExit: () {})));
    await tester.pumpAndSettle();

    final Finder list = find.byType(ListView);
    // 身份块吸顶：横屏常驻栏里一滚就丢身份，所以它必须在列表之外。
    expect(
      find.descendant(of: list, matching: findText('爱丽丝')),
      findsNothing,
    );
    // 离开固定底部：它现在混在滚动流最后，列表一长就找不到。
    expect(
      find.descendant(of: list, matching: findText('返回主应用')),
      findsNothing,
    );
    // 导航与分组标题在列表里（可滚动）。
    expect(find.descendant(of: list, matching: findText('推荐')), findsOneWidget);
    expect(find.descendant(of: list, matching: findText('社区')), findsOneWidget);
  });

  testWidgets('登录后点身份块进「我」', (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 't',
      user: <String, dynamic>{'username': 'alice', 'nickname': '爱丽丝'},
    );
    AppNavTarget? picked;
    await tester.pumpWidget(
      host(
        AppDrawerContent(
          selected: AppNavTarget.recommend,
          onSelect: (AppNavTarget t) => picked = t,
          onLogin: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(findText('爱丽丝'));
    await tester.pump();
    expect(picked, AppNavTarget.me);
  });
}
