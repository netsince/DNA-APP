import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// 简易 SharedPreferences 实例缓存。
///
/// SharedPreferences.getInstance() 首次会做磁盘 IO 解析，重复调用虽然后续
/// 会命中内部缓存，但仍是 async 且有额外调度开销。这里在 `main()` 里预热
/// 一次，供全应用同步复用，减少启动与各处的等待。
class SharedPrefs {
  SharedPrefs._();

  static Future<SharedPreferences>? _instance;

  /// 返回单例（首次调用时已由 [init] 预热）。
  static Future<SharedPreferences> get instance async {
    final cached = _instance;
    if (cached != null) return cached;
    final created = SharedPreferences.getInstance();
    _instance = created;
    return created;
  }

  /// 启动前预热，确保首次 getInstance 不在首帧期间阻塞。
  static Future<void> init() async {
    await instance;
  }

  /// 仅测试用：清空已缓存的单例，使下一次 [instance] 重新初始化。
  /// 用于在用例之间隔离 SharedPreferences 的 mock 存储。
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
