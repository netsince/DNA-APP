import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/prompt_strategy_advanced_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「高级」页的渲染与交互契约。
///
/// 这些页面太容易「编译通过、渲染为空」——静态检查看不出来，
/// 所以这里真的把它渲染出来，并验证「点预设会写回设置」。
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

/// FitText 继承自 Text，find.text 会把外层 FitText 和内层 Text 都命中。
/// 只取 `runtimeType == Text` 的那一个，保证每个文案恰好一个匹配。
Finder findText(String s) => find.byWidgetPredicate(
  (Widget w) => w.runtimeType == Text && (w as Text).data == s,
);

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
    // 页面很长且是 ListView（懒构建），把测试视口放宽，让所有分区都被构建，
    // 否则「结局收束」这类靠后的标题根本不会出现在树上。
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      MaterialApp(home: PromptStrategyAdvancedPage(controller: c)),
    );
    await t.pumpAndSettle();
  }

  testWidgets('页面渲染出预设方案与各主轴', (WidgetTester t) async {
    final AppController c = await boot();
    await pumpPage(t, c);

    expect(findText('预设方案'), findsOneWidget);
    expect(findText('视角与人称'), findsOneWidget);
    expect(findText('叙事结构'), findsOneWidget);
    expect(findText('节奏与张力'), findsOneWidget);
    expect(findText('信息揭示'), findsOneWidget);
    expect(findText('冲突来源'), findsOneWidget);
    // 折叠区默认收起，但标题要在
    expect(findText('结局收束'), findsOneWidget);
    expect(findText('意象母题'), findsOneWidget);
  });

  testWidgets('默认没有任何冲突提示', (WidgetTester t) async {
    final AppController c = await boot();
    await pumpPage(t, c);
    expect(findText('冲突提示'), findsNothing);
  });

  testWidgets('点预设会写回设置，并填出对应项', (WidgetTester t) async {
    final AppController c = await boot();
    await pumpPage(t, c);

    await t.tap(findText('悬疑本'));
    await t.pumpAndSettle();

    final details = c.settings.promptStrategy.details;
    expect(details.reveal, isNotNull);
    expect(details.revealMaxPerTurn, 1);
    expect(details.conflictSecondary, isNotNull);
  });

  testWidgets('点清除会回到全部未设置', (WidgetTester t) async {
    final AppController c = await boot();
    await pumpPage(t, c);

    await t.tap(findText('电影感'));
    await t.pumpAndSettle();
    expect(c.settings.promptStrategy.details.isEmpty, isFalse);

    await t.tap(findText('清除'));
    await t.pumpAndSettle();
    expect(c.settings.promptStrategy.details.isEmpty, isTrue);
  });

  testWidgets('预设不动基础项', (WidgetTester t) async {
    final AppController c = await boot();
    await pumpPage(t, c);

    final before = c.settings.promptStrategy;
    await t.tap(findText('网文爽'));
    await t.pumpAndSettle();
    final after = c.settings.promptStrategy;

    expect(after.advance, before.advance);
    expect(after.immersion, before.immersion);
    expect(after.length, before.length);
  });
}
