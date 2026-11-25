import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开场动画的「启动失败保险」。
///
/// 目的：如果启动页反复把进程搞崩（最典型是着色器在个别机型上初始化失败），
/// 用户会陷在「打开 → 崩 → 打开 → 崩」的死循环里，连设置页都进不去。
/// 这里在连续失败 [maxConsecutiveFailures] 次后，把开场动画自动关掉，
/// 让下一次启动能直接进软件 —— 用户进去后仍可在设置里重新打开。
///
/// ## 为什么是「先记账、后销账」
///
/// 崩溃时进程直接没了，写不进任何东西。所以只能在**启动页出现之前**先把
/// 「我在尝试启动」记进档案；只有动画完整播完才算这次启动成功，把档案清零。
/// 下次启动读到上一轮留下的计数，就知道有几轮没走完。
///
/// ## 记的是什么
///
/// 只记在 SharedPreferences（本机），不进 AppSettings：这是本机的启动健康状况，
/// 不是用户配置，跟着备份/迁移走反而会在新设备上误判。
class SplashCrashGuard {
  SplashCrashGuard({SharedPreferences? prefs}) : _injectedPrefs = prefs;

  /// 连续失败到这个次数就关掉开场动画。
  static const int maxConsecutiveFailures = 3;

  /// 存储键。带版本号：以后要改语义（比如改成记时间）可以换新键，
  /// 旧值自然被忽略，不用写迁移。
  static const String prefsKey = 'splash_boot_attempts_v1';

  final SharedPreferences? _injectedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  /// 当前累计的连续失败次数。
  Future<int> attempts() async {
    try {
      final SharedPreferences prefs = await _prefs();
      return prefs.getInt(prefsKey) ?? 0;
    } catch (e) {
      debugPrint('[splash-guard] 读启动计数失败: $e');
      return 0;
    }
  }

  /// 启动页即将出现：记一次尝试，返回**是否已经连续失败到该关掉动画**。
  ///
  /// [animationEnabled] 为 false 时不记账：本来就没动画可关，再记下去
  /// 只会在用户重新打开动画后立刻被判定为「失败过」，把功能锁死。
  Future<bool> registerAttempt({required bool animationEnabled}) async {
    if (!animationEnabled) return false;
    final int next = await attempts() + 1;
    try {
      final SharedPreferences prefs = await _prefs();
      if (next >= maxConsecutiveFailures) {
        // 到阈值：立刻清零。关掉动画之后就没必要继续累计了；
        // 万一这次仍然崩（不是动画的问题），用户下次进来动画也已经是关的，
        // 不会因为计数残留而反复触发。
        await prefs.remove(prefsKey);
        return true;
      }
      await prefs.setInt(prefsKey, next);
      return false;
    } catch (e) {
      // 写不进去就当没这回事：不能因为保险机制本身失败而阻断启动。
      debugPrint('[splash-guard] 写启动计数失败: $e');
      return false;
    }
  }

  /// 启动页走完了：销账。
  ///
  /// 以「动画完整播完」为成功界限，而不是「进入主界面之后」：进主界面那一步
  /// 掺杂了数据加载、网络、社区预热，那些地方出问题不该怪到开场动画头上，
  /// 也不该因此把用户的动画设置抹掉。
  Future<void> markSucceeded() async {
    try {
      final SharedPreferences prefs = await _prefs();
      if (prefs.containsKey(prefsKey)) await prefs.remove(prefsKey);
    } catch (e) {
      debugPrint('[splash-guard] 清零启动计数失败: $e');
    }
  }

  /// 测试用：清空档案。
  @visibleForTesting
  Future<void> debugReset() async {
    final SharedPreferences prefs = await _prefs();
    await prefs.remove(prefsKey);
  }
}
