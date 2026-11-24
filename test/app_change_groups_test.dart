import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
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
  Future<void> deleteConversation(String id) async {}
  @override
  Future<void> clearAll() async {}
}

/// 通知分组的机制锁。
///
/// 目的不是「少发几次通知」这种指标，而是**会不会发错组**：设置变更打到数据组，
/// 会让首页跟着设置页一起重建；反过来数据变更只发设置组，就是页面不再刷新。
/// 两种错都不会崩、不会有编译错误 —— 只能靠测试钉住。
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

  test('设置变更只打设置组，且不再发整体通知', () async {
    final AppController c = await boot();
    int settings = 0, data = 0, chat = 0, all = 0;
    c.settingsChanges.addListener(() => settings++);
    c.dataChanges.addListener(() => data++);
    c.chatChanges.addListener(() => chat++);
    c.addListener(() => all++);

    await c.patchSettings('themeMode', 'dark');

    expect(settings, greaterThan(0), reason: '设置组应当被通知');
    expect(data, 0, reason: '设置变更不该惊动数据组');
    expect(chat, 0, reason: '设置变更不该惊动聊天组');
    expect(all, 0, reason: '整体通知已撤，只能走分组');
  });

  test('数据变更只打数据组', () async {
    final AppController c = await boot();
    int settings = 0, data = 0, chat = 0;
    c.settingsChanges.addListener(() => settings++);
    c.dataChanges.addListener(() => data++);
    c.chatChanges.addListener(() => chat++);

    await c.deleteTa('not-a-real-id');

    expect(data, greaterThan(0), reason: '数据组应当被通知');
    expect(settings, 0, reason: '删除角色卡不该惊动设置组');
    expect(chat, 0);
  });

  test('全局动作通知全部三组', () async {
    final AppController c = await boot();
    int settings = 0, data = 0, chat = 0;
    c.settingsChanges.addListener(() => settings++);
    c.dataChanges.addListener(() => data++);
    c.chatChanges.addListener(() => chat++);

    await c.clearAllData();

    expect(settings, greaterThan(0));
    expect(data, greaterThan(0));
    expect(chat, greaterThan(0));
  });
}
