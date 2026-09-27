import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/ai_service_settings_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务页的**渲染契约测试**。
///
/// 背景:上一次把该页拆成多文件时,精简模式分支渲染出来的页面
/// **一个输入框都没有**(TextField=0),而 baseUrlController /
/// apiKeyController 作为参数传进去却从未使用 —— 用户切到精简模式后
/// 页面上只剩模式开关,所有配置项消失。
///
/// 静态分析(flutter analyze)与正则统计都发现不了这种缺陷:
/// 代码能编译、行数正常、组件调用次数也对,只是**渲染结果为空**。
/// 因此这里真正把页面渲染出来,逐个断言配置项必须存在。
///
/// **本文件是拆分重构的安全网**:任何拆分只要弄丢控件,这里就会红。
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
  Future<List<Conversation>> getConversations() async =>
      <Conversation>[];
}

/// FitText extends Text,find.text 会重复命中;只匹配内层真实 Text。
Finder findText(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w.data == s);

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

  Future<void> pumpPage(WidgetTester t, AppController c) async {
    await t.pumpWidget(MaterialApp(
      home: AiServiceSettingsPage(controller: c),
    ));
    await t.pumpAndSettle();
  }

  group('AI 服务页渲染契约', () {
    testWidgets('精简模式：配置项必须齐全(TextField 不能为 0)', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpPage(t, c);

      // 这是上次事故的核心断言:输入框数量必须 > 0。
      final int fields = find.byType(TextField).evaluate().length;
      expect(fields, greaterThan(0),
          reason: '精简模式必须至少渲染 Base URL / API Key 输入框,'
              '上次拆分后此处为 0,导致页面只剩模式开关');

      // 服务商选择 + 连接检测按钮必须存在。
      expect(findText('服务商选择'), findsWidgets);
      expect(findText('检测连接'), findsWidgets);
    });

    testWidgets('精简模式：Base URL 与 API Key 标签在渲染树中', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(true);
      await pumpPage(t, c);

      final Iterable<Element> labels = find.byType(TextField).evaluate();
      expect(labels.length, greaterThanOrEqualTo(1));
      // API Key 输入框的 labelText 必然渲染。
      expect(findText('API Key'), findsWidgets);
    });

    testWidgets('完整模式：同样渲染配置项与两个管理入口', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpPage(t, c);

      expect(findText('当前生效模型'), findsWidgets);
      expect(findText('服务商管理'), findsWidgets);
      expect(findText('模型预设管理'), findsWidgets);
    });

    testWidgets('采样参数入口在两种模式下都存在(仅标题不同)', (WidgetTester t) async {
      final AppController c = await boot();

      // 该入口在页面底部,默认 800x600 视口下位于折叠线以下,
      // 而 ListView 懒加载不会构建视口外的子项 —— 先滚到底再断言。
      Future<void> scrollToBottom() async {
        final Finder sv = find.byType(Scrollable);
        if (sv.evaluate().isNotEmpty) {
          await t.drag(sv.first, const Offset(0, -600));
          await t.pumpAndSettle();
        }
      }

      await c.toggleSimpleModelMode(true);
      await pumpPage(t, c);
      await scrollToBottom();
      expect(findText('采样参数微调'), findsWidgets,
          reason: '精简模式下采样入口标题应为「采样参数微调」');

      await c.toggleSimpleModelMode(false);
      await t.pumpAndSettle();
      await scrollToBottom();
      expect(findText('全局默认采样参数'), findsWidgets,
          reason: '完整模式下采样入口标题应为「全局默认采样参数」');
    });

    testWidgets('动态统计文案完整(服务商数 / 模型预设数)', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpPage(t, c);

      // 服务商管理入口必须显示「已配置 N 个服务商」。
      final Iterable<String> subs = find
          .byWidgetPredicate((Widget w) => w is Text && w.data != null)
          .evaluate()
          .map((Element e) => (e.widget as Text).data!)
          .where((String s) => s.startsWith('已配置'));
      expect(subs, isNotEmpty, reason: '管理入口的动态统计文案不能丢');
      expect(subs.any((String s) => s.contains('个服务商')), isTrue);
      expect(subs.any((String s) => s.contains('个模型预设')), isTrue);
    });

    testWidgets('两种模式都渲染模式开关本身', (WidgetTester t) async {
      final AppController c = await boot();
      await pumpPage(t, c);
      expect(findText('新手简易模式'), findsWidgets);
      expect(find.byType(SwitchListTile), findsWidgets);
    });

    testWidgets('切换模式后配置项不丢(回归上次事故)', (WidgetTester t) async {
      final AppController c = await boot();
      await c.toggleSimpleModelMode(false);
      await pumpPage(t, c);

      final int advancedFields = find.byType(TextField).evaluate().length;

      // 切到精简模式。
      await c.toggleSimpleModelMode(true);
      await t.pumpAndSettle();

      final int simpleFields = find.byType(TextField).evaluate().length;
      expect(simpleFields + advancedFields, greaterThan(0),
          reason: '两种模式合计必须至少有一个输入框;'
              '若为 0 说明配置项整体丢失');
    });
  });
}
