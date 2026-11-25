import 'package:dna/models/app_settings.dart';
import 'package:dna/pages/splash/splash_animations.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/splash_crash_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动页连续崩 3 次 → 自动关掉开场动画。
///
/// 崩溃时进程直接没了，来不及写任何东西，所以只能验「先记账、后销账」这套约定：
/// 记账在动画起播前，销账在动画播完后。这里按启动序列逐步模拟。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('启动计数', () {
    test('前两次不关，第三次到阈值并清零', () async {
      final SplashCrashGuard guard = SplashCrashGuard();

      expect(await guard.registerAttempt(animationEnabled: true), isFalse);
      expect(await guard.attempts(), 1);

      expect(await guard.registerAttempt(animationEnabled: true), isFalse);
      expect(await guard.attempts(), 2);

      expect(await guard.registerAttempt(animationEnabled: true), isTrue);
      expect(await guard.attempts(), 0, reason: '到阈值后要清零，避免反复触发');
    });

    test('成功走完一次就销账，不会累到第 3 次', () async {
      final SplashCrashGuard guard = SplashCrashGuard();

      await guard.registerAttempt(animationEnabled: true);
      await guard.registerAttempt(animationEnabled: true);
      await guard.markSucceeded();

      expect(await guard.attempts(), 0);
      expect(await guard.registerAttempt(animationEnabled: true), isFalse);
      expect(await guard.attempts(), 1);
    });

    test('本来就没开动画：不记账', () async {
      final SplashCrashGuard guard = SplashCrashGuard();
      expect(await guard.registerAttempt(animationEnabled: false), isFalse);
      expect(await guard.attempts(), 0,
          reason: '没动画可关时记账，会在用户重新打开动画后立刻误判');
    });

    test('档案被写成别的类型时当作 0，不抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SplashCrashGuard.prefsKey: 'not-an-int',
      });
      final SplashCrashGuard guard = SplashCrashGuard();
      expect(await guard.attempts(), 0);
      expect(await guard.registerAttempt(animationEnabled: true), isFalse);
    });
  });

  group('和设置联动', () {
    test('连续崩 3 次 → 设置里的动画变成「关闭」，且派生结果就是关闭', () async {
      final SettingsService service = SettingsService();
      final SplashCrashGuard guard = SplashCrashGuard();

      // 模拟三次「打开就崩」：每次都记了账，但都没走到销账。
      await guard.registerAttempt(animationEnabled: true);
      await guard.registerAttempt(animationEnabled: true);
      final bool shouldDisable =
          await guard.registerAttempt(animationEnabled: true);
      expect(shouldDisable, isTrue);

      // 启动外壳在这一步做的正是下面两行：写回 none，再按新值派生。
      final AppSettings before = await service.load();
      expect(before.splashAnimation, kDefaultSplashAnimationId);
      final AppSettings after =
          before.copyWith(splashAnimation: kSplashAnimationOffId);
      await service.save(after);

      final AppSettings reloaded = await service.load();
      expect(reloaded.splashAnimation, kSplashAnimationOffId);
      final SplashAnimationSpec spec = effectiveSplashAnimation(
        storedId: reloaded.splashAnimation,
        completedOobe: reloaded.completedOobe,
      );
      expect(spec.enabled, isFalse, reason: '禁用后应直接进主界面');
    });

    test('「关闭」压过引导期的液态玻璃', () async {
      // 否则禁用等于没禁用：引导没走完的用户还会继续看到液态玻璃。
      expect(
        effectiveSplashAnimationId(
          storedId: kSplashAnimationOffId,
          completedOobe: false,
        ),
        kSplashAnimationOffId,
      );
    });
  });
}
