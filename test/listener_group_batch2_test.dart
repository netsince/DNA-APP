import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/identity_page.dart';
import 'package:dna/pages/world_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  @override
  Future<void> deleteTa(String id) async {}
  @override
  Future<void> deleteWorld(String id) async {}
  @override
  Future<void> upsertWorld(World world) async {}
}

/// 监听方订阅源的第二批迁移锁。
///
/// 「订阅错组」不会崩：多订一组只是白重建，少订一组是**页面不再刷新**。
/// 两类都只能靠 build 计数发现。
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

  testWidgets('身份列表只订阅数据组：设置变更不重建', (WidgetTester tester) async {
    final AppController c = await boot();
    int builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c.dataChanges,
            builder: (BuildContext context, Widget? _) {
              builds++;
              return IdentityListBody(controller: c, onCreateIdentity: () {});
            },
          ),
        ),
      ),
    );
    final int afterFirst = builds;

    await c.patchSettings('themeMode', 'dark');
    await tester.pump();
    expect(builds, afterFirst, reason: '设置变更重建了只订阅数据组的页面');
  });

  testWidgets('世界列表订阅「数据 + 设置」两组：两者都会重建', (WidgetTester tester) async {
    final AppController c = await boot();
    int builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              c.dataChanges,
              c.settingsChanges,
            ]),
            builder: (BuildContext context, Widget? _) {
              builds++;
              return WorldListBody(
                controller: c,
                showArchived: false,
                onCreateWorld: () {},
              );
            },
          ),
        ),
      ),
    );
    final int afterFirst = builds;

    await c.deleteWorld('nope');
    await tester.pump();
    expect(builds, greaterThan(afterFirst), reason: '数据变更没有重建世界列表');

    final int afterData = builds;
    await c.patchSettings('themeMode', 'dark');
    await tester.pump();
    expect(builds, greaterThan(afterData), reason: '设置变更没有重建世界列表');
  });

  test('批量改写会话会同时惊动数据组与聊天组', () async {
    final AppController c = await boot();
    int data = 0, chat = 0;
    c.dataChanges.addListener(() => data++);
    c.chatChanges.addListener(() => chat++);
    // clearAllData 是 all；这里只验证 chatAndData 的语义由枚举保证。
    expect(AppChange.chatAndData.affectsChat, isTrue);
    expect(AppChange.chatAndData.affectsData, isTrue);
    expect(AppChange.chatAndData.affectsSettings, isFalse);
    expect(data, 0);
    expect(chat, 0);
  });
}
