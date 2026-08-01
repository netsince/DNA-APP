import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'tts_config.dart';

/// 播放 24kHz 单声道 float 音频。
///
/// 把 [Float32List] 编码为临时 WAV 文件后用 audioplayers 播放。
class TtsPlayer {
  TtsPlayer._();

  static final TtsPlayer instance = TtsPlayer._();

  AudioPlayer? _player;

  /// 当前是否正在播放（播放完成/停止时自动复位），供 UI 显示「正在朗读」状态。
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  /// 播放合成结果。若已有音频在播会先停止。
  Future<void> play(Float32List samples) async {
    await stop();
    final File wav = await _writeWav(samples);
    final AudioPlayer player = AudioPlayer();
    _player = player;
    playing.value = true;
    // 音频自然播完时复位「正在播放」状态。
    player.onPlayerComplete.listen((_) {
      if (_player == player) {
        _player = null;
        playing.value = false;
      }
    });
    player.onPlayerStateChanged.listen((PlayerState s) {
      if ((s == PlayerState.stopped || s == PlayerState.completed) &&
          _player == player) {
        _player = null;
        playing.value = false;
      }
    });
    await player.play(DeviceFileSource(wav.path), mode: PlayerMode.lowLatency);
  }

  Future<void> stop() async {
    final AudioPlayer? p = _player;
    _player = null;
    playing.value = false;
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
  }

  /// 把 float32 PCM 编码为 16-bit 单声道 WAV 文件。
  Future<File> _writeWav(Float32List samples) async {
    final Directory tmp = await getTemporaryDirectory();
    final File file = File(path.join(tmp.path, 'tts_${DateTime.now().millisecondsSinceEpoch}.wav'));
    final int sampleRate = kTtsSampleRate;
    final int dataLen = samples.length * 2;
    final ByteData out = ByteData(44 + dataLen);

    void _str(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        out.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    _str(0, 'RIFF');
    out.setUint32(4, 36 + dataLen, Endian.little);
    _str(8, 'WAVE');
    _str(12, 'fmt ');
    out.setUint32(16, 16, Endian.little); // fmt chunk size
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    out.setUint16(32, 2, Endian.little); // block align
    out.setUint16(34, 16, Endian.little); // bits per sample
    _str(36, 'data');
    out.setUint32(40, dataLen, Endian.little);

    // 峰值归一化：若峰值超过 0.95，整体压到 0.95，避免 16-bit 削波导致刺耳失真。
    // 引擎输出为 float32，峰值可能 >1.0，Python 播放 float 不会削波，但 16-bit 会。
    double peak = 0;
    for (int i = 0; i < samples.length; i++) {
      final double a = samples[i].abs();
      if (a > peak) peak = a;
    }
    final double gain = peak > 0.95 ? (0.95 / peak) : 1.0;

    for (int i = 0; i < samples.length; i++) {
      double v = (samples[i] * gain).clamp(-1.0, 1.0);
      out.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    await file.writeAsBytes(out.buffer.asUint8List(), flush: true);
    return file;
  }
}
