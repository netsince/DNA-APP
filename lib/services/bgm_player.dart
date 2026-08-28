import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 角色卡背景音乐播放器（单例）。
///
/// 职责：
/// - 循环播放某角色绑定的音乐文件（`ReleaseMode.loop`）；
/// - 音量受设置（`AppSettings.bgmVolume`）控制；
/// - 提供 `duck`/`unduck`：当 TTS 朗读或语音识别进行时，把背景音乐音量
///   临时调小，避免遮挡台词朗读/识别人声，结束自动恢复。
///
/// 生命周期由聊天页驱动：进入聊天页有音乐则 `play`，退出/切换聊天页则 `stop`。
/// 同一时刻只允许播放一个角色的背景音乐。
class BgmPlayer {
  BgmPlayer._();

  static final BgmPlayer instance = BgmPlayer._();

  AudioPlayer? _player;
  String? _currentPath;
  bool _playing = false;

  /// 设置中配置的基础音量（0~1）。播放/duck 时按此换算实际音量。
  double _baseVolume = 0.5;

  /// 是否正处于「降音量」状态（TTS 朗读 / 语音识别进行中）。
  bool _ducked = false;

  /// 当前是否有音乐在播放，供 UI（聊天页三点菜单勾选）显示。
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  /// 当前播放的音乐路径（无则 null）。
  String? get currentPath => _currentPath;

  /// 设置基础音量（0~1），由调用方在设置变化时同步。
  void setBaseVolume(double v) {
    _baseVolume = v.clamp(0.0, 1.0);
    _applyVolume();
  }

  /// 播放指定音乐（循环）。若正是同一文件且在播则忽略；否则停旧播新。
  Future<void> play(String path) async {
    if (path.isEmpty) return;
    if (_playing && _currentPath == path) {
      return;
    }
    await stop();
    try {
      final AudioPlayer player = AudioPlayer();
      _player = player;
      _currentPath = path;
      _playing = true;
      isPlaying.value = true;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_effectiveVolume());
      await player.play(DeviceFileSource(path), mode: PlayerMode.lowLatency);
    } catch (_) {
      // 播放失败（文件损坏/不存在等）时复位，不向 UI 抛错。
      await _reset();
    }
  }

  /// 暂停当前音乐（保留进度）。
  Future<void> pause() async {
    if (_player == null || !_playing) return;
    try {
      await _player!.pause();
      _playing = false;
      isPlaying.value = false;
    } catch (_) {}
  }

  /// 继续播放已暂停的音乐。
  Future<void> resume() async {
    if (_player == null || _currentPath == null) return;
    if (_playing) return;
    try {
      await _player!.resume();
      _playing = true;
      isPlaying.value = true;
    } catch (_) {}
  }

  /// 停止并释放播放器。
  Future<void> stop() async {
    final AudioPlayer? p = _player;
    _player = null;
    _currentPath = null;
    _playing = false;
    _ducked = false;
    isPlaying.value = false;
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
  }

  /// 临时调小背景音乐音量（TTS 朗读 / 语音识别开始时调用）。
  Future<void> duck() async {
    if (_ducked || _player == null) return;
    _ducked = true;
    await _applyVolume();
  }

  /// 恢复背景音乐音量（TTS 朗读 / 语音识别结束时调用）。
  Future<void> unduck() async {
    if (!_ducked) return;
    _ducked = false;
    await _applyVolume();
  }

  double _effectiveVolume() {
    if (!_playing || _player == null) return 0.0;
    // 被降音时只保留约 25%，其余音量放回人声。
    return _ducked ? _baseVolume * 0.25 : _baseVolume;
  }

  Future<void> _applyVolume() async {
    final AudioPlayer? p = _player;
    if (p == null) return;
    try {
      await p.setVolume(_effectiveVolume());
    } catch (_) {}
  }

  Future<void> _reset() async {
    final AudioPlayer? p = _player;
    _player = null;
    _currentPath = null;
    _playing = false;
    _ducked = false;
    isPlaying.value = false;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
