import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 开场动画的时钟：**按累加的时间走，掉帧只会变慢，绝不会跳帧**。
///
/// 为什么不用 `AnimationController`：它是「按墙钟时间推进」的——冷启动时第一帧
/// 可能被着色器管线创建、纹理上传、启动期任务卡住好几百毫秒甚至一秒多，那一帧
/// 一掉，动画就直接快进同样长的时间。实测冷启动时 2.6 秒的动画只剩最后 0.9 秒
/// 被看见，就是这个原因。
///
/// 这里每帧只取「和上一帧的间隔」，并夹到 [maxStep]（默认 50ms）以内，再累加。
/// 卡多久都不会跳；代价只是卡的时候动画走慢一点，看起来仍然是连续的。
class SplashClock extends ChangeNotifier {
  SplashClock({
    required TickerProvider vsync,
    required this.duration,
    this.maxStep = const Duration(milliseconds: 50),
  }) {
    _ticker = vsync.createTicker(_onTick);
  }

  final Duration duration;

  /// 单帧最多推进多少。50ms ≈ 20fps：够宽容，又不会让卡顿变成跳跃。
  final Duration maxStep;

  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  /// 上一帧的累计时间。**不能用 0 当哨兵**：Ticker 的第一帧就是 0，
  /// 那样会把真正的第二帧也当成「第一帧」吞掉。
  Duration? _lastTick;
  bool _started = false;
  bool _done = false;
  VoidCallback? _onComplete;

  /// 0..1 的进度。
  double get value {
    if (duration.inMicroseconds <= 0) return 1;
    return (_elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  bool get isDone => _done;

  /// 等到**首帧真正画出来之后**再起钟。
  ///
  /// 在 initState 里直接起钟是不行的：从起钟到第一次真正上屏之间，光栅线程还要
  /// 建管线、传纹理，那段时间会把动画的开头吃掉。这里挂一帧回调，让首帧先上屏。
  void startAfterFirstFrame({VoidCallback? onComplete}) {
    _onComplete = onComplete;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_done) return;
      _started = true;
      _lastTick = null;
      _ticker.start();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _onTick(Duration elapsed) {
    if (!_started || _done) return;
    // 第一帧没有「上一帧」，直接记下来，不推进。
    final Duration? last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    Duration delta = elapsed - last;
    if (delta.isNegative) delta = Duration.zero;
    if (delta > maxStep) delta = maxStep;
    _elapsed += delta;
    if (_elapsed >= duration) {
      _elapsed = duration;
      _finish();
    }
    notifyListeners();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    final VoidCallback? done = _onComplete;
    _onComplete = null;
    notifyListeners();
    done?.call();
  }

  /// 立即结束（着色器加载失败等兜底路径用）。
  void finishNow() {
    _elapsed = duration;
    _finish();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
