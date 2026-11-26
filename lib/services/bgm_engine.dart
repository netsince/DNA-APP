import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'audio_output.dart';

/// 播放引擎上报的事件，供 `BgmPlaybackController` 校正自己的意图。
///
/// 只保留状态机能用上的四种：`completed` / `stopped` 是「我不该停但我停了」的
/// 证据，`playing` / `paused` 只用于观测（状态机不据此改变意图，避免回声）。
enum BgmEngineEvent { completed, stopped, playing, paused }

/// 背景音乐播放引擎：`BgmPlaybackController` 唯一的底层依赖。
///
/// 存在这层抽象的唯一理由：状态机（音量不变量 / 播完从头再来 / 意图与真实
/// 播放状态一致）必须能脱离平台插件被测试。`AudioPlayer` 在构造时就注册平台
/// 通道，`flutter test` 里没有原生实现，没法直接驱动。
abstract class BgmEngine {
  /// 打开（切换）到指定文件并开始播放。重复调用同一路径不应打断当前进度。
  Future<void> open(String path);

  /// 从当前位置继续播放。
  Future<void> play();

  Future<void> pause();

  /// 停止并释放当前音源的位置（下次 [open] 从 0 开始）。
  Future<void> stop();

  Future<void> seekToStart();

  Future<void> setVolume(double volume);

  /// 原生播放器的事件流。
  Stream<BgmEngineEvent> get events;

  Future<void> dispose();
}

/// 基于 audioplayers 的实现（全平台）。
class AudioplayersBgmEngine implements BgmEngine {
  AudioplayersBgmEngine() {
    _completeSub = _player.onPlayerComplete.listen(
      (_) => _emit(BgmEngineEvent.completed),
    );
    _stateSub = _player.onPlayerStateChanged.listen(_onPlayerState);
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<BgmEngineEvent> _events =
      StreamController<BgmEngineEvent>.broadcast();

  late final StreamSubscription<void> _completeSub;
  late final StreamSubscription<PlayerState> _stateSub;

  /// 已经交给原生播放器的音源路径；null 表示没有（或已被 [stop] 清掉）。
  String? _openedPath;
  bool _configured = false;

  @override
  Stream<BgmEngineEvent> get events => _events.stream;

  @override
  Future<void> open(String path) async {
    await _ensureConfigured();
    if (_openedPath == path) {
      // 同一首曲子重复进入：接着放，不要从头打断。
      await _player.resume();
      return;
    }
    _openedPath = path;
    // 模式/上下文/循环已在 _ensureConfigured 里落地，这里不要再传 mode：
    // `play(mode:)` 会在设源之后重建播放器（WrappedPlayer.playerMode 的 setter
    // 会 release + init），白丢一次 prepared。
    await _player.play(DeviceFileSource(path));
  }

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _openedPath = null;
    await _player.stop();
  }

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() async {
    await _completeSub.cancel();
    await _stateSub.cancel();
    await _events.close();
    await _player.dispose();
  }

  /// 一次性配置：顺序有意义（先模式、再上下文、最后循环），
  /// 见 [kLongAudioPlayerMode] 与 [buildCoexistingAudioContext] 的说明。
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    await _player.setPlayerMode(kLongAudioPlayerMode);
    await _player.setAudioContext(buildCoexistingAudioContext());
    // 能由原生循环完成的事先交给原生；Dart 侧的重来只是兜底（见状态机注释）。
    await _player.setReleaseMode(ReleaseMode.loop);
  }

  void _onPlayerState(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
        _emit(BgmEngineEvent.playing);
      case PlayerState.paused:
        _emit(BgmEngineEvent.paused);
      case PlayerState.stopped:
        _emit(BgmEngineEvent.stopped);
      case PlayerState.completed:
        _emit(BgmEngineEvent.completed);
      case PlayerState.disposed:
        break;
    }
  }

  void _emit(BgmEngineEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}
