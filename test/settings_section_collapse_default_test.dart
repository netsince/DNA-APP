import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/appearance_display_page.dart';
import 'package:dna/pages/settings/appearance_display_spec.dart';
import 'package:dna/pages/settings/spec/settings_fields_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字段页的分组默认折叠策略：一页七八组时只展开第一组。
///
/// 三条豁免各自对应一种「收起来反而更差」的情况，都要有测试兜着：
/// 项数太少的组、搜索命中的组、以及永远展开的第一组。
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

  /// 视口开高一点：外观页分组多，矮视口下下面的组压根没建出来。
  Future<void> pumpPage(
    WidgetTester tester,
    AppController c, {
    Widget? page,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: page ?? AppearanceDisplayPage(controller: c)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('第一组默认展开、项多的第二组默认收起', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);

    // 第一组（明暗与配色）——默认展开
    expect(find.text('明暗与配色'), findsWidgets);
    expect(find.text('明暗外观').hitTestable(), findsWidgets,
        reason: '第一组必须展开，否则一进页面什么都看不到');

    // 「界面元素」组项数 >= 3 ——默认收起
    expect(find.text('界面元素'), findsWidgets);
    expect(find.text('聊天输入栏样式').hitTestable(), findsNothing,
        reason: '项多的组默认收起，标题仍在、内容不在');

    // 点标题展开
    await tester.tap(find.text('界面元素').first);
    await tester.pumpAndSettle();
    expect(find.text('聊天输入栏样式').hitTestable(), findsWidgets);
  });

  testWidgets('项数少的组默认展开（收起来只是多点一次）',
      (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);

    // 「应用图标」组只有一条，低于阈值，应默认展开。
    expect(find.text('应用图标').hitTestable(), findsWidgets,
        reason: '项数 < kAutoExpandItemThreshold 的组不该收起');
  });

  testWidgets('搜索命中的组会展开，哪怕它在后面', (WidgetTester tester) async {
    final AppController c = await boot();
    // 直接渲染字段页并指定命中项，模拟从搜索跳进来。
    await pumpPage(
      tester,
      c,
      page: SettingsFieldsPage(
        entry: appearanceEntry,
        controller: c,
        focusItemId: 'appearance.chatInputStyle',
      ),
    );

    expect(find.text('聊天输入栏样式').hitTestable(), findsWidgets,
        reason: '命中的项必须看得见，否则搜索跳转等于没跳');
  });
}
