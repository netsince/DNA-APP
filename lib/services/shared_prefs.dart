import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// 全应用**唯一**的 SharedPreferences 访问入口。
///
/// 以前 prefs 有三套访问方式：
/// 1. island 端的这个缓存包装（只在 4 个文件里用）；
/// 2. 主程序 20 处直接 `SharedPreferences.getInstance()`；
/// 3. `SettingsService` 自己一套 `_readInt` / `_writeInt` 小工具。
///
/// 现在统一走这里：改缓存策略、加日志、换实现都只改一个地方。
///
/// **刻意不在这里再缓存一层。** `shared_preferences` 插件内部已经缓存了实例
/// （`getInstance()` 返回同一个 Future），再包一层 cache 只会让
/// `SharedPreferences.setMockInitialValues` 在测试里失效——插件会把内部实例
/// 重置成 mock，而我们的 cache 仍指向旧的。之前这一层缓存就是靠
/// `resetForTest()` 手动补票的。
class SharedPrefs {
  SharedPrefs._();

  static Future<SharedPreferences> get instance =>
      SharedPreferences.getInstance();

  /// 启动前预热（让首次 `getInstance` 不落在首帧）。
  static Future<void> init() async {
    await instance;
  }

  /// 保留给已有测试调用。
  ///
  /// 现在是 no-op：实例由插件自己管理，`setMockInitialValues` 之后
  /// 下一次 `getInstance()` 自然拿到 mock。保留方法是为了不让调用点改动。
  @visibleForTesting
  static void resetForTest() {}
}
