import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/ai_service_more_page.dart';
import 'package:dna/pages/settings/ai_service_settings_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务页 + 「⋮」分栏页的**渲染契约测试**。
///
/// 背景:本页曾被拆坏过一次 —— 精简模式渲染出来一个输入框都没有,
/// 而 `flutter analyze` 干净、行数正常、组件调用次数也对,
/// 只是**渲染结果为空**。静态手段查不出来,所以这里真正渲染并断言。
///
/// 重构后结构:
/// * 主页:精简模式 = 连接参数 + 模型选择;完整模式 = 平铺模型列表;
/// * 右上角 `⋮` = [AiServiceMorePage],精简模式只有「其他」tab、
///   完整模式有「模型 / 服务商 / 其他」;
/// * 简易模式开关与全局采样参数都在「其他」tab 里。
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

/// FitText extends Text,find.text 会重复命中;只匹配内层真实 Text。
Finder findText(String s) =>
    find.byWidgetPredicate((Widget w) => w is Text && w.data == s);

void main() {
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

  Future<void> pumpHome(WidgetTester t, AppController c) async {
    await t.pumpWidget(MaterialApp(home: AiServiceSettingsPage(controller: c)));
    await t.pumpAndSettle();
  }

  Future<void> pumpMore(WidgetTester t, AppController c) async {
    await t.pumpWidget(MaterialApp(home: AiServiceMorePage(controller: c)));
    await t.pumpAndSettle();
  }

  group('AI 服务主页', () {
    testWidgets('精简模式：Base URL / API Key 输入框必须存在', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpHome(t, c);

      final int fields = find.byType(TextField).evaluate().length;
      expect(fields, greaterThan(0),
          reason: '精简模式必须渲染连接参数输入框;'
              '此前拆分事故中此处为 0,页面只剩模式开关');
      expect(findText('服务商选择'), findsWidgets);
      expect(findText('检测连接'), findsWidgets);
    });

    testWidgets('精简模式：不再显示模式开关与采样入口', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpHome(t, c);

      expect(findText('新手简易模式'), findsNothing,
          reason: '模式开关已移到 ⋮ → 其他');
      expect(findText('采样参数微调'), findsNothing,
          reason: '采样参数已移到 ⋮ → 其他');
    });

    testWidgets('完整模式：平铺模型列表,且不再有快速切换按钮', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpHome(t, c);

      expect(findText('快速切换'), findsNothing,
          reason: '模型已平铺,不再需要快速切换入口');
      expect(find.byType(ListTile), findsWidgets,
          reason: '模型应以列表项平铺渲染');
    });

    testWidgets('完整模式：管理入口已移走', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpHome(t, c);

      expect(findText('服务商管理'), findsNothing);
      expect(findText('模型预设管理'), findsNothing);
    });

    testWidgets('右上角必须有「⋮」入口', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpHome(t, c);
      expect(find.byIcon(Icons.more_vert), findsWidgets);
    });
  });

  group('⋮ 分栏页', () {
    testWidgets('精简模式：只有「其他」,没有分栏栏', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpMore(t, c);

      expect(findText('其他'), findsNothing, reason: '只有一栏时不显示 TabBar');
      expect(find.byType(TabBar), findsNothing);
      // 「其他」栏的两样东西必须都在。
      expect(findText('新手简易模式'), findsWidgets);
      expect(findText('全局默认采样参数'), findsWidgets);
    });

    testWidgets('完整模式：三个分栏齐全', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpMore(t, c);

      expect(find.byType(TabBar), findsOneWidget);
      expect(findText('模型'), findsWidgets);
      expect(findText('服务商'), findsWidgets);
      expect(findText('其他'), findsWidgets);
    });

    testWidgets('完整模式：切到「其他」栏能看到开关与采样', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpMore(t, c);

      await t.tap(findText('其他').last);
      await t.pumpAndSettle();

      expect(findText('新手简易模式'), findsWidgets,
          reason: '完整模式也必须能切回简易模式,否则进去就出不来');
      expect(findText('全局默认采样参数'), findsWidgets,
          reason: '完整模式也必须能调采样参数');
    });

    testWidgets('完整模式：模型栏渲染列表,服务商栏渲染卡片', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpMore(t, c);

      // 第一栏是模型列表。
      expect(find.byType(ListView), findsWidgets);

      // 切到服务商栏。
      await t.tap(findText('服务商').last);
      await t.pumpAndSettle();
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('其他栏的开关能真正切换模式', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpMore(t, c);

      await t.tap(findText('其他').last);
      await t.pumpAndSettle();

      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();

      expect(c.settings.simpleModelMode, isTrue,
          reason: '开关必须真的写入设置');
    });

    testWidgets('在「其他」栏切换简易模式后,分栏栏立刻反映(无需退出重进)',
        (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpMore(t, c);

      // 完整模式:三栏 + TabBar。
      expect(find.byType(TabBar), findsOneWidget);

      // 切到「其他」栏,打开简易模式。
      await t.tap(findText('其他').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();

      // 不退出本页 —— TabBar 必须当场消失,且直接显示「其他」栏内容。
      expect(c.settings.simpleModelMode, isTrue);
      expect(find.byType(TabBar), findsNothing,
          reason: '切到精简模式后 TabBar 应当场消失,'
              '用户不必退出页面再进来');
      expect(findText('新手简易模式'), findsWidgets,
          reason: '精简模式下应当场显示「其他」栏内容');

      // 再切回完整模式,三栏要回来,且停在「其他」栏。
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(find.byType(TabBar), findsOneWidget,
          reason: '切回完整模式后三栏应当场恢复');
      expect(findText('新手简易模式'), findsWidgets,
          reason: '恢复后应仍停在「其他」栏(索引钉在 2),'
              '而不是跳到「模型」栏导致内容与标题对不上');
    });

    testWidgets('在 ⋮ 里改模式后,返回主页立刻生效', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpHome(t, c);

      // 完整模式主页应无输入框。
      expect(find.byType(TextField).evaluate().length, 0);

      // 进入 ⋮ → 其他 → 打开简易模式。
      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      await t.tap(findText('其他').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();

      // 返回主页。
      await t.pageBack();
      await t.pumpAndSettle();

      // 主页必须已经切成精简模式(出现输入框)。
      expect(find.byType(TextField).evaluate().length, greaterThan(0),
          reason: '主页用 AnimatedBuilder 监听 controller,'
              'toggleSimpleModelMode 会 notifyListeners,返回后应立刻反映新模式');
    });
  });
}
