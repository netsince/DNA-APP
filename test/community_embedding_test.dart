import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/app_drawer.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/widgets/drag_scroll_behavior.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/community_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';

/// 社区嵌进主项目后的**副作用边界**。
///
/// 用户反馈的一组偶发问题，根子都在同一件事上：栏目壳的「胶片」会把**途经**
/// 栏目也真的挂载起来，而社区挂载 = 一整套岛的外壳 + 一堆副作用：
///
/// * 弹站点公告（模态遮罩会把侧边栏的点击吞掉）；
/// * 各页面弹 SnackBar（被主项目根部的 messenger 画到主应用底部，人走了提示还在）；
/// * 侧栏「登录」是个没接回调的死按钮（岛独立运行时就一直这样）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CommunityPreload.instance.resetForTest);

  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_oobe': true,
      'show_bottom_nav': false,
    });
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
          useMaterial3: true,
          fontFamily: AppFont.family,
        ),
        home: Scaffold(body: child),
      );

  Finder findText(String s) => find.byWidgetPredicate(
        (Widget w) => w is Text && w.data == s && w is! FitText,
      );

  AppSectionShellState shellOf(WidgetTester tester) =>
      tester.state<AppSectionShellState>(find.byType(AppSectionShell));

  group('社区只在真正进入时挂载', () {
    testWidgets('从世界滑到设置、途经社区时不挂载岛（只有静态占位）',
        (WidgetTester tester) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AppSectionShell(controller: c)));
      await tester.pumpAndSettle();

      // 抽屉顺序：home / 群聊 / 我家 / 世界 / 身份 / 社区 / 设置。
      // 世界(3) → 设置(6) 会依次掠过 身份(4) 与 社区(5)。
      shellOf(tester).navigateTo(AppSection.world);
      await tester.pumpAndSettle();
      shellOf(tester).navigateTo(AppSection.settings);

      bool sawPlaceholder = false;
      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        if (find.byType(SectionPassingPlaceholder).evaluate().isNotEmpty) {
          sawPlaceholder = true;
        }
        expect(
          find.byType(CommunityBody),
          findsNothing,
          reason: '社区只是途经页，不该把岛挂载起来（会弹公告/弹提示/吞点击）',
        );
      }
      expect(sawPlaceholder, isTrue, reason: '途经社区时应该显示静态占位');
      await tester.pumpAndSettle();
    });

    testWidgets('真正进入社区时才挂载（并且岛内提示走社区自己的 messenger）',
        (WidgetTester tester) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AppSectionShell(controller: c)));
      await tester.pumpAndSettle();
      shellOf(tester).navigateTo(AppSection.world);
      await tester.pumpAndSettle();

      // 底栏横向顺序里社区紧挨着世界：世界(3) → 社区(4)。
      shellOf(tester).navigateTo(AppSection.community, axis: Axis.horizontal);
      // 起飞后的第一帧动画值还是 0（页面尚未进入视口），推进两帧再看。
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(CommunityBody), findsOneWidget,
          reason: '进入社区要真的挂载');

      await tester.pumpAndSettle();
      expect(find.byType(CommunityBody), findsOneWidget);
      // 社区自带一个 ScaffoldMessenger：岛内的 SnackBar 不再外泄到主应用。
      expect(
        find.descendant(
          of: find.byType(CommunityBody),
          matching: find.byType(ScaffoldMessenger),
        ),
        findsOneWidget,
      );
    });
  });

  group('社区侧栏的登录按钮', () {
    testWidgets('未登录时「登录」是可点的（回调接上了）', (WidgetTester tester) async {
      int tapped = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            height: 800,
            child: AppDrawerContent(
              selected: AppNavTarget.recommend,
              onSelect: (_) {},
              onLogin: () => tapped++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(AuthSession.instance.isLoggedIn, isFalse);
      await tester.tap(findText('登录'));
      await tester.pump();
      expect(tapped, 1, reason: 'onLogin 未接时 ListTile.onTap 是 null，按钮点不动');
    });

    test('岛外壳必须把 onLogin 接上（曾经是死按钮）', () {
      final String src =
          File('lib/island_app/root_shell.dart').readAsStringSync();
      expect(src.contains('onLogin:'), isTrue,
          reason: '不传 onLogin 的话，侧栏那行「登录」看着正常但完全点不动');
      expect(
        RegExp(r'onLogin:\s*\(\)\s*=>\s*_onSelectNav\(AppNavTarget\.me\)')
            .hasMatch(src),
        isTrue,
        reason: '登录表单在「我」页，登录入口应切到那一页',
      );
    });

    test('顶栏未读数不能写在 build 里（每 rebuild 一次就发一次请求）', () {
      // 真事故：应用在电脑上「疯狂地无法连接」，浏览器和手机却正常。
      //
      // 根因不是网络不通，而是请求自己把连接池占满了 —— 其中一个放大器就是
      // 顶栏那个未读数：future 写在 build 里，而 _topBar() 是在 build() 里调
      // 的，于是 RootShell 每 rebuild 一次就发一次请求。配合「每次尝试 15 秒
      // 超时」和 maxConnectionsPerHost = 4，几次交互就能让后续所有请求排队
      // 等死。它只在登录后渲染，所以未登录时完全看不出来。
      final String src =
          File('lib/island_app/root_shell.dart').readAsStringSync();
      expect(
        RegExp(r'future:\s*ApiClient\.instance').hasMatch(src),
        isFalse,
        reason: 'build 里不能直接发请求：换成 StatefulWidget，在 initState 里拉一次',
      );
      expect(
        src.contains('class _NotificationButton'),
        isTrue,
        reason: '未读数应在一个 StatefulWidget 里只拉一次（从通知页回来再刷新）',
      );
    });
  });
  group('社区预热的数据', () {
    test('表情目录加载失败后允许重试（一次抖动不会把整个会话钉死）', () async {
      StickerCatalog.instance.debugClear();
      addTearDown(StickerCatalog.instance.debugClear);

      // 测试环境没有服务器地址：这次加载必然失败。
      final Future<void> first = StickerCatalog.instance.ensureLoaded();
      await first;
      expect(StickerCatalog.instance.loaded, isFalse);

      // 关键：第二次必须是**新的一次加载**，而不是命中上次那个已完成的 Future。
      final Future<void> second = StickerCatalog.instance.ensureLoaded();
      expect(identical(first, second), isFalse,
          reason: '失败后应重新发起请求，否则表情包这一整个会话都不会再加载');
      await second;
    });
  });
  group('举报提交', () {
    test('提交回调的形参形式必须与 ApiClient.submitReport 一致', () {
      // 这一行是**编译期**守护：两者形参形式不一致时（曾经：typedef 用位置
      // 参数、实现用命名参数），`?? ` 表达式的类型会退化成 Function，编译不
      // 报错、调用时才抛 NoSuchMethodError —— 举报就这么静默坏掉过。
      final ReportSubmitter submitter = ApiClient.instance.submitReport;
      expect(submitter, isNotNull);
    });
  });

  group('电脑版靠拖的界面', () {
    test('DragScrollBehavior 放开鼠标与触控板拖拽', () {
      const DragScrollBehavior behavior = DragScrollBehavior();
      expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
      expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
      expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    });

    test('岛的正文层与图片预览画廊都套了这个 behavior', () {
      // Flutter 桌面默认把鼠标排除在 dragDevices 之外：不套的话「刷一刷」
      // 这个 PageView 在电脑版上按住鼠标拖毫无反应。
      final String shell =
          File('lib/island_app/root_shell.dart').readAsStringSync();
      expect(shell.contains('DragScrollBehavior()'), isTrue,
          reason: '刷一刷/横向筛选条靠拖，电脑版必须放开鼠标拖拽');
      final String viewer =
          File('lib/island_app/widgets/image_viewer.dart').readAsStringSync();
      expect(viewer.contains('DragScrollBehavior()'), isTrue);
    });
  });

  group('图片预览手势', () {
    test('只允许上下拖拽退出，左右滑动留给切图', () {
      final String src =
          File('lib/island_app/widgets/image_viewer.dart').readAsStringSync();
      expect(src.contains('slideAxis: SlideAxis.vertical'), isTrue);
      expect(src.contains('slideAxis: SlideAxis.both'), isFalse,
          reason: 'both 会把水平拖拽也当成退出，多图左右滑动总被打断');
    });
  });
}

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
