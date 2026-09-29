import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/pages/conversation_create_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/widgets/app_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 各栏目页的颜色(页面级 ColoredBox,查找与几何断言用)。
Color pageColor(int i) => Color(0xFF000000 | (0x111111 * (i + 1)));

/// 构造一个可驱动的飞行宿主:6 个假栏目页(body),
/// 用 AnimationController 手动推进进度,断言各阶段视口里是谁。
///
/// 方向约定(与实现一致):胶片向负方向滑——旧内容从上/左退出,
/// 新内容从下/右进入(标准"下一页"走向)。
Future<AnimationController> pumpFlight(
  WidgetTester tester, {
  Axis axis = Axis.vertical,
  int fromIndex = 0,
  int toIndex = 3,
}) async {
  final AnimationController controller = AnimationController(
    vsync: tester,
    duration: sectionTravelDuration((toIndex - fromIndex).abs()),
  );
  const List<AppSection> sections = AppSection.values;
  final List<Widget> pages = <Widget>[
    for (int i = 0; i < sections.length; i++)
      ColoredBox(
        color: pageColor(i),
        child: Center(child: Text('栏目$i')),
      ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: sectionFlight(
        animation: controller,
        axis: axis,
        fromIndex: fromIndex,
        toIndex: toIndex,
        sections: sections,
        pages: pages,
      ),
    ),
  );
  return controller;
}

Finder pageAt(int i) => find.byWidgetPredicate(
  (Widget w) => w is ColoredBox && w.color == pageColor(i),
);

/// 与渲染测试共用的轻量引导:假 Hive,真实设置/服务。
class FakeHiveService extends HiveService {
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

/// FitText 是 Text 子类且内部再包一层 Text,谓词须排除 FitText
/// 本身,只匹配内层真实 Text(否则 '消息' 恒命中 2 个)。
Finder findText(String s) => find.byWidgetPredicate(
  (Widget w) => w is Text && w.data == s && w is! FitText,
);

void main() {
  /// 轻量引导:假 Hive + 真实设置/服务。
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: FakeHiveService(),
    );
    await c.initialize();
    return c;
  }

  testWidgets('纵向飞行 首页(0)→世界(3):途经页逐个掠过,远端页不挂载', (WidgetTester tester) async {
    final AnimationController controller = await pumpFlight(
      tester,
      fromIndex: 0,
      toIndex: 3,
    );

    // t=0:只有起点页在场。
    controller.value = 0;
    await tester.pump();
    expect(pageAt(0), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(3), findsNothing);

    // t=0.06 → 缓动约 0.49(前段陡:小进度已滑近半程)→ 已滑约 1.46 步:
    // 起点页出局(-1.46),栏目1(-0.46)与栏目2(+0.54)在场,
    // 目标页栏目3(+1.54)尚未挂载。
    controller.value = 0.06;
    await tester.pump();
    expect(pageAt(0), findsNothing);
    expect(pageAt(1), findsOneWidget);
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsNothing);

    // t=0.16 → 缓动约 0.73 → 已滑约 2.18 步:
    // 栏目2(-0.18)与目标页(+0.82)在场,栏目1 已出局(-1.18),
    // 栏目4(+1.82)永不出场。
    controller.value = 0.16;
    await tester.pump();
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(4), findsNothing);

    // t=1:只剩目标页。
    controller.value = 1;
    await tester.pump();
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(0), findsNothing);
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsNothing);
    controller.dispose();
  });

  testWidgets('横向飞行 群聊(1)→世界(3):掠过我家(2),不经过主页(0)', (WidgetTester tester) async {
    final AnimationController controller = await pumpFlight(
      tester,
      axis: Axis.horizontal,
      fromIndex: 1,
      toIndex: 3,
    );

    // t=0.09 → 缓动约 0.58 → 已滑约 1.16 步:我家(-0.16)在视口
    // 掠过,世界(+0.84)进入中;主页(-1.16 反方向)出局。
    controller.value = 0.09;
    await tester.pump();
    expect(pageAt(2), findsOneWidget);
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(0), findsNothing);

    controller.value = 1;
    await tester.pump();
    expect(pageAt(3), findsOneWidget);
    expect(pageAt(1), findsNothing);
    expect(pageAt(2), findsNothing);
    controller.dispose();
  });

  testWidgets('偏移几何:位移 = -缓动进度 × 视口,方向为负,无交叉轴分量', (WidgetTester tester) async {
    AnimationController controller = await pumpFlight(
      tester,
      axis: Axis.horizontal,
      fromIndex: 0,
      toIndex: 1,
    );
    // 任意原始进度:起点页向左退出 -eased×w,目标页从右侧
    // (1-eased)×w 处趋近。视口宽取页面实例自身的宽
    // (Positioned 强制其等于视口)。
    const double raw = 0.09;
    controller.value = raw;
    await tester.pump();
    final Rect p0 = tester.getRect(pageAt(0));
    final Rect p1 = tester.getRect(pageAt(1));
    final double eased = AppMotion.travel.transform(raw);
    expect(p0.left, closeTo(-eased * p0.width, 0.5));
    expect(p1.left, closeTo((1 - eased) * p1.width, 0.5));
    expect(p0.top, 0); // 横向飞行:无纵向分量
    expect(p0.left, lessThan(0)); // 方向:旧页向左退出
    expect(p1.left, greaterThan(0)); // 目标页从右侧趋近
    controller.dispose();

    controller = await pumpFlight(
      tester,
      axis: Axis.vertical,
      fromIndex: 0,
      toIndex: 1,
    );
    controller.value = raw;
    await tester.pump();
    final Rect v0 = tester.getRect(pageAt(0));
    final Rect v1 = tester.getRect(pageAt(1));
    final double easedV = AppMotion.travel.transform(raw);
    expect(v0.top, closeTo(-easedV * v0.height, 0.5));
    expect(v1.top, closeTo((1 - easedV) * v1.height, 0.5));
    expect(v0.left, 0); // 纵向飞行:无横向分量
    expect(v0.top, lessThan(0)); // 方向:旧页向上退出
    expect(v1.top, greaterThan(0)); // 目标页从底侧趋近
    controller.dispose();
  });

  testWidgets('时长随距离递增且封顶', (WidgetTester tester) async {
    expect(sectionTravelDuration(1), AppMotion.sectionTravel);
    expect(sectionTravelDuration(2), const Duration(milliseconds: 390));
    expect(sectionTravelDuration(3), const Duration(milliseconds: 480));
    expect(sectionTravelDuration(10), AppMotion.sectionTravelCap);
  });

  testWidgets('栏目壳:框架(底栏/标题栏)不动,内容区滑到目标栏目', (WidgetTester tester) async {
    final AppController c = await boot();
    // 打开底栏(默认关闭),验证框架固定 + 横向飞行。
    await c.saveShowBottomNav(true);

    // 竖屏窗口:走抽屉 + 底栏分支。
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AppSectionShell(controller: c)));
    await tester.pumpAndSettle();

    // 初始:首页标题 + 底栏,底栏第一项选中。
    expect(findText('消息'), findsOneWidget);
    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(bar.selectedIndex, 0);

    // 底栏点「世界」:横向飞行(底栏顺序:主页0 → 群聊1 → 我家2 → 世界3)。
    tester
        .state<AppSectionShellState>(find.byType(AppSectionShell))
        .navigateTo(AppSection.world, axis: Axis.horizontal);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // 飞行中段

    // 框架不动:底栏仍然在场,选中项立即切到目标(位置固定的证据)。
    final NavigationBar barMid = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(barMid.selectedIndex, 3);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 标题栏槽位已切到目标栏目(旧标题消失;
    // 「世界」与底栏 label 重名,以「消息」清零为标题切换的证据)。
    expect(findText('消息'), findsNothing);

    await tester.pumpAndSettle();
    // 落定:只剩世界内容,旧标题仍不在场。
    expect(findText('消息'), findsNothing);
    expect(findText('世界归档'), findsNothing);
    final NavigationBar barEnd = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(barEnd.selectedIndex, 3);
  });

  testWidgets('右上角按钮:从图标位置放大为页面,关闭后缩回原位', (WidgetTester tester) async {
    final AppController c = await boot();
    // 竖屏窗口:与真实使用一致(标题栏 + 底栏)。
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AppSectionShell(controller: c)));
    await tester.pumpAndSettle();

    // 右上角动作是**容器变换**而不是 MaterialPageRoute:
    // 关闭态圆形、底色 = AppBar 背景(静止时隐形)、
    // 点击由 IconButton 自己发起(容器不抢手势)。
    final Finder plus = find.byTooltip('新建会话');
    final AppContainer<bool> action = tester.widget<AppContainer<bool>>(
      find.ancestor(of: plus, matching: find.byType(AppContainer<bool>)),
    );
    expect(action.closedShape, isA<CircleBorder>());
    expect(action.tappable, isFalse);
    final ColorScheme cs = Theme.of(
      tester.element(find.byType(AppSectionShell)),
    ).colorScheme;
    expect(action.closedColor, cs.surface);

    // 起飞:容器从图标位置放大成页面。
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.byType(ConversationCreatePage), findsOneWidget);

    // 关闭:缩回图标原位,回到首页。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ConversationCreatePage), findsNothing);
    expect(findText('消息'), findsOneWidget);
  });
}
