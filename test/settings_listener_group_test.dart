import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/appearance_display_spec.dart';
import 'package:dna/pages/settings/spec/settings_fields_page.dart';
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
}

/// 设置页只订阅「设置组」：数据变更不该重建它。
///
/// 这条锁的是分组的**实际收益**：以前订阅整个 controller，聊天流里每个 chunk
/// 触发会话 upsert（数据组）都会把设置页重建一次。改错了不会崩，只会白重建。
void main() {
  testWidgets('设置变更会重建，数据变更不会', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();

    int builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: c.settingsChanges,
          builder: (BuildContext context, Widget? _) {
            builds++;
            return Text(c.settings.themeMode);
          },
        ),
      ),
    );
    expect(builds, 1);

    // 数据变更：不该重建。
    await c.deleteTa('nope');
    await tester.pump();
    expect(builds, 1, reason: '数据变更重建了设置订阅方');

    // 设置变更：必须重建。
    await c.patchSettings('themeMode', 'dark');
    await tester.pump();
    expect(builds, 2, reason: '设置变更没有重建订阅方');
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('设置字段页整体能渲染（回归）', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    await tester.pumpWidget(
      MaterialApp(home: SettingsFieldsPage(entry: appearanceEntry, controller: c)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsFieldsPage), findsOneWidget);
  });
}
