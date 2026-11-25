import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/pages/splash/splash_animations.dart';
import 'package:dna/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动（未完成引导）用液态玻璃、引导完成后换回默认描边的契约。
///
/// 两件事分开验：
/// * 派生：本轮该播哪段只由 `completedOobe` 决定，不落盘；
/// * 落盘：`completeOobe()` 必须把设置里的动画改成默认值，
///   否则用户第一次正常启动还会看到引导期的亮相。
/// 只提供空数据：本文件只关心设置那一层。
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
  Future<AppController> bootController() async {
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

  group('本次启动该播哪段', () {
    test('未完成引导：一律液态玻璃，不看设置里的值', () {
      // 即使存档里写着 fade，也还是引导期的动画 —— 那时用户没机会改。
      expect(
        effectiveSplashAnimationId(
          storedId: 'fade',
          completedOobe: false,
        ),
        kFirstRunSplashAnimationId,
      );
      expect(kFirstRunSplashAnimationId, 'glassLogo');
    });

    test('已完成引导：用设置里存的 id', () {
      expect(
        effectiveSplashAnimationId(
          storedId: 'fade',
          completedOobe: true,
        ),
        'fade',
      );
      expect(
        effectiveSplashAnimationId(
          storedId: kSplashAnimationOffId,
          completedOobe: true,
        ),
        kSplashAnimationOffId,
      );
    });

    test('返回的 spec 与 id 对得上，且引导期那段真能播', () {
      // 存档里是别的动画（用户改过 / 老存档），引导期仍然走首次启动那段。
      final SplashAnimationSpec firstRun = effectiveSplashAnimation(
        storedId: 'fade',
        completedOobe: false,
      );
      expect(firstRun.id, kFirstRunSplashAnimationId);
      expect(firstRun.enabled, isTrue, reason: '引导期那段必须是能播的');

      final SplashAnimationSpec after = effectiveSplashAnimation(
        storedId: kSplashAnimationOffId,
        completedOobe: true,
      );
      expect(after.id, kSplashAnimationOffId);
      expect(after.enabled, isFalse);
    });

    test('「关闭」即使在引导期也生效', () {
      // 启动失败保险会写 none；如果引导期派生把它顶回液态玻璃，禁用就等于没做。
      final SplashAnimationSpec off = effectiveSplashAnimation(
        storedId: kSplashAnimationOffId,
        completedOobe: false,
      );
      expect(off.id, kSplashAnimationOffId);
      expect(off.enabled, isFalse);
    });

    test('默认动画就是描边（引导完成后落到的那一段）', () {
      expect(kDefaultSplashAnimationId, 'logoDraw');
      expect(
        effectiveSplashAnimationId(
          storedId: kDefaultSplashAnimationId,
          completedOobe: true,
        ),
        effectiveSplashAnimationId(
          storedId: 'logoDraw',
          completedOobe: true,
        ),
      );
    });
  });

  group('完成引导时的落盘', () {
    test('completeOobe 把动画改成默认描边，并标记已完成', () async {
      final AppController c = await bootController();
      // 先把存档改成别的动画，确保不是「本来就是这个值」蒙对。
      await c.patchSettings('splashAnimation', 'fade');
      expect(c.settings.splashAnimation, 'fade');

      await c.completeOobe();

      expect(c.settings.completedOobe, isTrue);
      expect(c.settings.splashAnimation, kDefaultSplashAnimationId,
          reason: '引导完成后应换回默认描边，不再保留引导期的亮相');
    });
  });

  group('设置层', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('全新的设置：未完成引导、存的是默认动画', () async {
      final AppSettings s = await SettingsService().load();
      expect(s.completedOobe, isFalse);
      expect(s.splashAnimation, kDefaultSplashAnimationId);
      // 于是首次启动派生出液态玻璃
      expect(
        effectiveSplashAnimationId(
          storedId: s.splashAnimation,
          completedOobe: s.completedOobe,
        ),
        kFirstRunSplashAnimationId,
      );
    });

    test('引导完成后设置里的动画变成默认值', () async {
      final SettingsService service = SettingsService();
      final AppSettings before =
          (await service.load()).copyWith(splashAnimation: 'fade');
      await service.save(before);

      // 模拟 completeOobe 的写入（控制器那层要 Hive，这里只验设置通道）。
      final AppSettings after =
          before.copyWith(
            completedOobe: true,
            splashAnimation: kDefaultSplashAnimationId,
          );
      await service.save(after);

      final AppSettings reloaded = await service.load();
      expect(reloaded.completedOobe, isTrue);
      expect(reloaded.splashAnimation, kDefaultSplashAnimationId);
      expect(
        effectiveSplashAnimationId(
          storedId: reloaded.splashAnimation,
          completedOobe: reloaded.completedOobe,
        ),
        kDefaultSplashAnimationId,
      );
    });
  });
}
