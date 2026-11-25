import 'package:dna/bootstrap_app.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/splash_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/splash_crash_guard.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动外壳的接线：记账到阈值时真的把设置改成「关闭」，并且不再渲染启动页。
///
/// 决策本身在 `splash_crash_guard_test.dart` 单测；这里验的是**接错就白干**的那一层。
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
  Future<AppController> pumpBootstrap(
    WidgetTester tester, {
    required Map<String, Object> prefs,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await tester.pumpWidget(BootstrapApp(controller: c));
    // 设置读取 → 记账 → 写回 → 初始化，都是异步的，逐帧推过去。
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return c;
  }

  testWidgets('已连续失败 2 次：这一轮到阈值，动画被关掉且不再渲染启动页',
      (WidgetTester tester) async {
    final AppController c = await pumpBootstrap(
      tester,
      prefs: <String, Object>{
        'auto_backup': false,
        'completed_oobe': true,
        'splash_animation': 'logoDraw',
        SplashCrashGuard.prefsKey: 2,
      },
    );

    expect(c.settings.splashAnimation, 'none',
        reason: '到阈值要把设置写回「关闭」，否则下次启动还会崩');
    expect(find.byType(SplashPage), findsNothing);
    expect(await SplashCrashGuard().attempts(), 0, reason: '到阈值后档案要清零');
  });

  testWidgets('只失败过 1 次：照常播动画，档案继续累计', (WidgetTester tester) async {
    final AppController c = await pumpBootstrap(
      tester,
      prefs: <String, Object>{
        'auto_backup': false,
        'completed_oobe': true,
        'splash_animation': 'logoDraw',
        SplashCrashGuard.prefsKey: 1,
      },
    );

    expect(c.settings.splashAnimation, 'logoDraw', reason: '没到阈值不该动设置');
    expect(find.byType(SplashPage), findsOneWidget);
    expect(await SplashCrashGuard().attempts(), 2);
  });

  testWidgets('本来就是「关闭动画」：不记账，也不因为失败过 3 次而误判',
      (WidgetTester tester) async {
    await pumpBootstrap(
      tester,
      prefs: <String, Object>{
        'auto_backup': false,
        'completed_oobe': true,
        'splash_animation': 'none',
        SplashCrashGuard.prefsKey: 2,
      },
    );

    expect(find.byType(SplashPage), findsNothing);
    expect(await SplashCrashGuard().attempts(), 0,
        reason: '没动画时顺手清掉旧档案');
  });
}
