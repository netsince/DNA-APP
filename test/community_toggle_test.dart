import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/home_body.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_bottom_nav.dart';
import 'package:dna/widgets/app_drawer.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「社区」开关（默认开）与社区隐藏预热的行为测试。
///
/// 用户反馈：有人不习惯社区内嵌在手机 APP 里 —— 关掉后底部导航、侧边栏
/// 与滑动顺序里都不该再出现社区，也不该再为它做任何初始化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 与 app_section_test 共用的轻量引导：假 Hive + 真实设置/服务。
  Future<AppController> boot({required bool enableCommunity}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_oobe': true,
      'enable_community': enableCommunity,
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

  /// FitText 内部再包一层 Text，谓词排除 FitText 本身避免重复命中。
  Finder findText(String s) => find.byWidgetPredicate(
        (Widget w) => w is Text && w.data == s && w is! FitText,
      );

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
          useMaterial3: true,
          fontFamily: AppFont.family,
        ),
        home: Scaffold(body: child),
      );

  group('社区开关', () {
    test('关掉社区后，纵向与横向的滑动顺序都不再包含社区', () {
      // 开：两张表都在（社区在横向表末尾）。
      expect(sectionOrder(Axis.vertical), contains(AppSection.community));
      expect(sectionOrder(Axis.horizontal), contains(AppSection.community));

      // 关：两张表都摘掉，且**其余栏目的相对次序不变**。
      final List<AppSection> vertical =
          sectionOrder(Axis.vertical, enableCommunity: false);
      final List<AppSection> horizontal =
          sectionOrder(Axis.horizontal, enableCommunity: false);
      expect(vertical, isNot(contains(AppSection.community)));
      expect(horizontal, isNot(contains(AppSection.community)));
      expect(
        vertical,
        AppSection.values
            .where((AppSection s) => s != AppSection.community)
            .toList(),
      );
      expect(
        horizontal,
        kHorizontalSectionOrder
            .where((AppSection s) => s != AppSection.community)
            .toList(),
      );
    });

    testWidgets('默认（开）时底栏与侧边栏都有社区入口', (WidgetTester tester) async {
      final AppController c = await boot(enableCommunity: true);

      await tester.pumpWidget(
        host(AppBottomNav(controller: c, current: AppSection.home)),
      );
      expect(findText('社区'), findsOneWidget);
      expect(findText('世界'), findsOneWidget);

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: AppDrawer(
              controller: c,
              current: AppSection.home,
              persistent: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(findText('社区'), findsOneWidget);
      expect(findText('世界'), findsOneWidget);
    });

    testWidgets('关掉社区后底栏与侧边栏都没有社区入口', (WidgetTester tester) async {
      final AppController c = await boot(enableCommunity: false);

      await tester.pumpWidget(
        host(AppBottomNav(controller: c, current: AppSection.home)),
      );
      expect(findText('社区'), findsNothing);
      // 其余入口照旧（不是把底栏整条干掉）。
      expect(findText('世界'), findsOneWidget);
      expect(findText('主页'), findsOneWidget);

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: AppDrawer(
              controller: c,
              current: AppSection.home,
              persistent: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(findText('社区'), findsNothing);
      expect(findText('世界'), findsOneWidget);
      expect(findText('设置'), findsOneWidget);
    });

    testWidgets('关掉社区后底栏选中项不错位（世界仍是第 4 格）',
        (WidgetTester tester) async {
      final AppController c = await boot(enableCommunity: false);
      await tester.pumpWidget(
        host(AppBottomNav(controller: c, current: AppSection.world)),
      );
      final NavigationBar bar =
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 4);
      expect(bar.selectedIndex, 3);
    });

    testWidgets('侧边栏顺序：身份排在「世界」下面', (WidgetTester tester) async {
      final AppController c = await boot(enableCommunity: true);
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            height: 800,
            child: AppDrawer(
              controller: c,
              current: AppSection.home,
              persistent: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 抽屉顺序 = AppSection 枚举顺序，也就是纵向滑动的胶片顺序：
      // 上半区是四个常驻底栏栏目，身份/社区/设置在下半区。
      final double worldY = tester.getCenter(findText('世界')).dy;
      final double identityY = tester.getCenter(findText('身份')).dy;
      expect(worldY, lessThan(identityY), reason: '身份应在「世界」下面');
      expect(
        AppSection.values.indexOf(AppSection.world),
        lessThan(AppSection.values.indexOf(AppSection.identity)),
        reason: '枚举顺序（= 纵向滑动顺序）也必须一致',
      );
    });

    testWidgets('底栏只为「本来就在其中」的栏目渲染（身份/设置不在其中）',
        (WidgetTester tester) async {
      final AppController on = await boot(enableCommunity: true);
      expect(AppBottomNav.showsFor(on, AppSection.home), isTrue);
      expect(AppBottomNav.showsFor(on, AppSection.world), isTrue);
      expect(AppBottomNav.showsFor(on, AppSection.community), isTrue);
      // 身份/设置只从抽屉进：底栏里没有它们的位置。
      expect(AppBottomNav.showsFor(on, AppSection.identity), isFalse);
      expect(AppBottomNav.showsFor(on, AppSection.settings), isFalse);

      final AppController off = await boot(enableCommunity: false);
      expect(AppBottomNav.showsFor(off, AppSection.community), isFalse);
      expect(AppBottomNav.showsFor(off, AppSection.world), isTrue);
    });
  });

  group('社区隐藏预热', () {
    tearDown(CommunityPreload.instance.resetForTest);

    testWidgets('社区关闭时不做任何初始化', (WidgetTester tester) async {
      CommunityPreload.instance.resetForTest();
      CommunityPreload.instance.schedule(enabled: () => false);
      // 让 post-frame 回调跑掉。
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pump();

      expect(CommunityPreload.instance.isBooted, isFalse);
      expect(CommunityPreload.instance.needsSetup, isFalse);
    });

    test('预取结果有保鲜期：过期后不再复用', () {
      final CommunityPreload p = CommunityPreload.instance;
      p.resetForTest();

      p.setFeaturedForTest(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'c1'},
      ]);
      expect(p.freshFeaturedCards, isNotNull);

      p.setFeaturedForTest(
        <Map<String, dynamic>>[<String, dynamic>{'id': 'c1'}],
        fetchedAt: DateTime.now().subtract(
          CommunityPreload.freshFor + const Duration(seconds: 1),
        ),
      );
      expect(p.freshFeaturedCards, isNull);

      p.setFeaturedForTest(null);
      expect(p.freshFeaturedCards, isNull);
    });

    testWidgets('预取命中时首页直接铺内容（不转圈、不再请求）',
        (WidgetTester tester) async {
      final CommunityPreload p = CommunityPreload.instance;
      p.resetForTest();
      p.setFeaturedForTest(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'c1', 'name': '预热角色卡'},
      ]);

      await tester.pumpWidget(host(const HomeBody()));
      await tester.pump();

      // 卡片直接在场：既没有骨架屏，也没有「拉不到服务器」的错误态。
      expect(findText('预热角色卡'), findsOneWidget);
      expect(find.byType(Shimmer), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('没有预取时首页自己拉（此处没有服务器地址 → 错误态）',
        (WidgetTester tester) async {
      CommunityPreload.instance.resetForTest();

      await tester.pumpWidget(host(const HomeBody()));
      await tester.pump();
      await tester.pump();

      expect(findText('预热角色卡'), findsNothing);
      expect(find.byType(ErrorState), findsOneWidget);
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
