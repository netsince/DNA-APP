/// 「连点 N 次」计数器：用于把开发者选项藏在版本号后面。
///
/// 抽成纯逻辑是为了能直接单测（不依赖 widget）：
/// * 必须在 [resetAfter] 内连续点满 [requiredTaps] 次才算数；
/// * 点满后计数清零，所以**再点同样次数会反向切换**（解开 → 收起）。
class DeveloperUnlockCounter {
  DeveloperUnlockCounter({
    this.requiredTaps = 10,
    this.resetAfter = const Duration(seconds: 3),
  });

  final int requiredTaps;
  final Duration resetAfter;

  int _taps = 0;
  DateTime? _lastTap;

  int get taps => _taps;

  /// 记录一次点击。返回 true 表示刚好点满，调用方应切换解锁状态。
  bool tap(DateTime now) {
    final DateTime? last = _lastTap;
    if (last != null && now.difference(last) > resetAfter) {
      _taps = 0;
    }
    _lastTap = now;
    _taps++;
    if (_taps >= requiredTaps) {
      _taps = 0;
      _lastTap = null;
      return true;
    }
    return false;
  }

  /// 还差几次（用于提示「再点 N 次」）。点满时为 0。
  int get remaining => requiredTaps - _taps;
}
