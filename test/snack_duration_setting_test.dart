import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/utils/ui_feedback.dart';
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
}

/// 「提示条停留时长」这一项必须**真的能改**。
///
/// 审计 F-11 记的是：snackDurationMs 存得进 prefs、启动时也被读，
/// 但唯一能改它的 setter 已删（F-3），设置界面里也没有它 —— 用户永远改不动。
///
/// 现在它有了声明（appearance_display_spec 的一行）+ 唯一入口
/// `AppController.applySnackDuration`。这条测试锁两件事：
/// 1. 改得动（settings 里的值变了）；
/// 2. **真的生效**（后续 snackbar 用的就是新时长，而不是只存不生效）。
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

  test('改得动：applySnackDuration 会写进设置', () async {
    final AppController c = await boot();
    expect(c.settings.snackDurationMs, kDefaultSnackDurationMs);

    await c.applySnackDuration(7000);

    expect(c.settings.snackDurationMs, 7000);
  });

  testWidgets('真生效：之后的 snackbar 用新时长', (WidgetTester tester) async {
    final AppController c = await boot();
    await c.applySnackDuration(7000);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => TextButton(
              onPressed: () => showSnack(ctx, '提示'),
              child: const Text('弹'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('弹'));
    await tester.pump();

    final SnackBar bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(milliseconds: 7000));
  });
}
