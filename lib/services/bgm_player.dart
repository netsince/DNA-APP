import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'bgm_engine.dart';

/// 播放意图。状态机里唯一的真相来源：原生播放器的真实状态只用来**纠正**它，
/// 不用来定义它。
enum BgmIntent { idle, playing, paused }

/// 角色卡背景音乐状态机（纯 Dart，不碰平台通道，因此可测）。
///
/// 三条不变量（每一条都对应一次真实回归，改代码前先读这里）：
///
/// 1. **音量只有一个出口**：原生音量永远是
///    `baseVolume * (ducked ? kDuckFactor : 1)`，与「是否暂停」无关。
///    旧实现让「暂停中」的音量算出 0（`_effectiveVolume()` 在 `!_playing` 时
///    返回 0），而 `resume()` 又不重设音量 —— 于是切一次后台、或暂停期间
///    TTS 的 duck/unduck 落一次音量，音乐会「恢复播放但永远静音」。
///
/// 2. **播完必须从头再来**：只要意图是「在播」，引擎报 `completed` / `stopped`
///    就 seek(0) + play，并重新落一次音量。不依赖原生 `ReleaseMode.loop`
///    是否会上报完成（各平台行为不一致，不能拿来做保证）。
///
/// 3. **意图与真实状态不许分叉**：引擎的每一次调用失败都会把意图复位；
///    任何外部原因（被抢焦点、路由切换、被系统掐掉）导致的停止都会被
///    事件纠正回来。旧实现全程 `catch (_) {}` 且从不订阅播放器事件，
///    所以「停了」在应用内完全不可见，UI 一直显示在播。
class BgmPlaybackController {
  BgmPlaybackController(this._engine) {
    _sub = _engine.events.listen(_onEngineEvent);
  }

  /// 被 duck 时保留的音量比例（TTS 朗读 / 语音识别进行中）。
  static const double kDuckFactor = 0.25;

  /// 兜底重启的限流窗口：正常曲子几分钟才播完一次，永远撞不上；
  /// 撞上说明文件根本放不出来，继续重启只会空转（旧实现是静默放弃，
  /// 这里显式判定失败，让 `isPlaying` 说实话）。
  static const Duration kRestartWindow = Duration(seconds: 10);

  /// 一个窗口内最多重启几次。
  static const int kMaxRestartsPerWindow = 3;

  final BgmEngine _engine;
  late final StreamSubscription<BgmEngineEvent> _sub;

  BgmIntent _intent = BgmIntent.idle;
  String? _path;
  double _baseVolume = 0.5;
  bool _ducked = false;

  int _restarts = 0;
  DateTime? _lastRestartAt;

  /// 意图上是否在播，供 UI 显示。
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  String? get currentPath => _path;

  double get baseVolume => _baseVolume;

  bool get isDucked => _ducked;

  BgmIntent get intent => _intent;

  /// 当前应该落到原生播放器上的音量 —— **唯一出口**，见类注释不变量 1。
  double get effectiveVolume => _baseVolume * (_ducked ? kDuckFactor : 1.0);

  /// 设置基础音量（0~1），由调用方在设置变化时同步。
  Future<void> setBaseVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0);
    await _applyVolume();
  }

  /// 播放指定音乐（循环）。同一文件重复调用不打断正在播放的进度。
  Future<void> play(String path) async {
    if (path.isEmpty) return;
    final bool samePath = _intent != BgmIntent.idle && _path == path;
    _path = path;
    _setIntent(BgmIntent.playing);
    if (samePath) {
      await _guard(_engine.play);
    } else {
      await _guard(() => _engine.open(path));
    }
    await _applyVolume();
  }

  /// 暂停当前音乐（保留进度）。
  Future<void> pause() async {
    if (_intent != BgmIntent.playing) return;
    _setIntent(BgmIntent.paused);
    await _guard(_engine.pause);
  }

  /// 从暂停处继续播放，并**重新落一次音量**（不变量 1）。
  Future<void> resume() async {
    if (_intent != BgmIntent.paused) return;
    _setIntent(BgmIntent.playing);
    await _guard(_engine.play);
    await _applyVolume();
  }

  /// 停止并丢掉当前位置（下次 [play] 从 0 开始）。
  Future<void> stop() async {
    _path = null;
    _ducked = false;
    _restarts = 0;
    _lastRestartAt = null;
    _setIntent(BgmIntent.idle);
    await _guard(_engine.stop);
  }

  /// 临时调小音量（TTS 朗读 / 语音识别开始时调用）。
  Future<void> duck() async {
    if (_ducked) return;
    _ducked = true;
    await _applyVolume();
  }

  /// 恢复音量（TTS 朗读 / 语音识别结束时调用）。
  Future<void> unduck() async {
    if (!_ducked) return;
    _ducked = false;
    await _applyVolume();
  }

  Future<void> dispose() async {
    await _sub.cancel();
    isPlaying.dispose();
    await _engine.dispose();
  }

  /// 唯一的音量写入口（不变量 1 与 R8：状态下发只从这走）。
  ///
  /// 没有活动播放意图时**不写**：此时写下去的 0 会被下一次播放继承，
  /// 正是旧实现「回来就没声」的来源。
  Future<void> _applyVolume() async {
    if (_intent == BgmIntent.idle) return;
    await _guard(() => _engine.setVolume(effectiveVolume));
  }

  void _setIntent(BgmIntent intent) {
    _intent = intent;
    isPlaying.value = intent == BgmIntent.playing;
  }

  /// 所有引擎调用都从这里走：失败即复位意图，绝不让界面显示「在播」而实际没声。
  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (error) {
      debugPrint('[BgmPlayer] 播放器操作失败：$error');
      _setIntent(BgmIntent.idle);
    }
  }

  void _onEngineEvent(BgmEngineEvent event) {
    if (_intent != BgmIntent.playing) return;
    if (event != BgmEngineEvent.completed && event != BgmEngineEvent.stopped) {
      return;
    }
    unawaited(_restartFromStart());
  }

  /// 不变量 2：意图是「在播」但原生说结束了 —— 从 0 重来。
  Future<void> _restartFromStart() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastRestartAt;
    if (last != null && now.difference(last) > kRestartWindow) {
      _restarts = 0;
    }
    _lastRestartAt = now;
    _restarts++;
    if (_restarts > kMaxRestartsPerWindow) {
      debugPrint('[BgmPlayer] 音乐反复立刻结束，放弃自动重播（文件可能无法解码）');
      _setIntent(BgmIntent.idle);
      return;
    }
    await _guard(() async {
      await _engine.seekToStart();
      await _engine.play();
    });
    await _applyVolume();
  }
}

/// 应用生命周期 → 背景音乐动作。
///
/// 产品策略：**失焦即暂停**。所以 `inactive` 也算暂停 —— Android 上它是下拉通知
/// 栏、系统权限弹窗、来电浮层；桌面端是窗口失焦。`resumed` 才恢复。
///
/// 为什么把它做成纯函数而不是在调用点写 if：这条策略被来回改过（先「inactive 也
/// 暂停」→ 因 0 音量陷阱改成「只认真后台」→ 现在按产品要求改回「失焦暂停」）。
/// 写在页面回调里时，改一次就没有任何东西能守住它；做成数据 + 测试之后，改错立刻红。
///
/// 注意：`inactive` 暂停之所以现在安全，是因为音量不变量（见 [BgmPlaybackController]
/// 不变量 1）已经保证「暂停中不会把原生音量写成 0」，且 `resume()` 会重落音量。
enum BgmLifecycleAction { pause, resume, nothing }

BgmLifecycleAction bgmActionForLifecycle(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.inactive:
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:
    case AppLifecycleState.detached:
      return BgmLifecycleAction.pause;
    case AppLifecycleState.resumed:
      return BgmLifecycleAction.resume;
  }
}

/// 角色卡背景音乐播放器（单例）。
///
/// 生命周期由聊天页驱动：进入聊天页有音乐则 `play`，退出/切换聊天页则 `stop`，
/// 应用失焦或进入后台时 `pause`、回到前台 `resume`（见 [bgmActionForLifecycle]）。
/// 同一时刻只允许播放一个角色的音乐。
///
/// 逻辑全在 [BgmPlaybackController]；这一层只负责「有且只有一个引擎实例」。
class BgmPlayer {
  BgmPlayer._();

  static final BgmPlayer instance = BgmPlayer._();

  BgmPlaybackController? _controller;

  /// 首次真正用到播放能力时才构造引擎（`AudioPlayer` 会注册平台通道，
  /// 不希望在纯逻辑路径/测试里被顺带触发）。
  BgmPlaybackController get controller =>
      _controller ??= BgmPlaybackController(AudioplayersBgmEngine());

  /// 当前是否（意图上）在播，供 UI（聊天页三点菜单）显示。
  ValueNotifier<bool> get isPlaying => controller.isPlaying;

  /// 当前播放的音乐路径（无则 null）。
  String? get currentPath => controller.currentPath;

  /// 设置基础音量（0~1），由调用方在设置变化时同步。
  Future<void> setBaseVolume(double volume) => controller.setBaseVolume(volume);

  /// 播放指定音乐（循环）。若正是同一文件且在播则忽略；否则停旧播新。
  Future<void> play(String path) => controller.play(path);

  /// 暂停当前音乐（保留进度）。
  Future<void> pause() => controller.pause();

  /// 继续播放已暂停的音乐。
  Future<void> resume() => controller.resume();

  /// 停止并释放播放器。
  Future<void> stop() => controller.stop();

  /// 临时调小背景音乐音量（TTS 朗读 / 语音识别开始时调用）。
  Future<void> duck() => controller.duck();

  /// 恢复背景音乐音量（TTS 朗读 / 语音识别结束时调用）。
  Future<void> unduck() => controller.unduck();
}
