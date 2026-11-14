import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 桌面端（Windows）的 mp3/wav 播放器。
///
/// 为什么不用 audioplayers：这个构建里它每次播 mp3 都会在 MSVCP140 里崩
/// （0xc0000005），所以桌面端一直靠 dna-bridge 在外部播放。
/// 这里直接走 Windows 自带的 MCI（winmm.dll），零插件、零依赖，
/// 也让桌面端可以彻底去掉 node 桥。
class WinMciPlayer {
  WinMciPlayer._();

  static final WinMciPlayer instance = WinMciPlayer._();

  static const String _alias = 'dna_tts_cloud';

  static final DynamicLibrary _winmm = DynamicLibrary.open('winmm.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>)
      _mciSendString = _winmm.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>)>(
      'mciSendStringW');

  static final int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      _getShortPathName = _kernel32.lookupFunction<
          Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)>(
      'GetShortPathNameW');

  int _send(String command) {
    final Pointer<Utf16> cmd = command.toNativeUtf16();
    try {
      return _mciSendString(cmd, nullptr, 0, nullptr);
    } finally {
      calloc.free(cmd);
    }
  }

  String _query(String command) {
    const int capacity = 260;
    final Pointer<Utf16> cmd = command.toNativeUtf16();
    final Pointer<Utf16> buf = calloc<Uint16>(capacity).cast<Utf16>();
    try {
      final int rc = _mciSendString(cmd, buf, capacity, nullptr);
      if (rc != 0) return '';
      return buf.toDartString().trim();
    } finally {
      calloc.free(cmd);
      calloc.free(buf);
    }
  }

  /// 中文路径会让 MCI 的 open 失败，统一换成 8.3 短路径。
  String _asciiPath(String path) {
    try {
      final Pointer<Utf16> src = path.toNativeUtf16();
      final Pointer<Utf16> out = calloc<Uint16>(1024).cast<Utf16>();
      try {
        final int len = _getShortPathName(src, out, 1024);
        if (len > 0 && len < 1024) {
          final String short = out.toDartString();
          if (short.isNotEmpty && !short.contains(RegExp(r'[^\x20-\x7E]'))) {
            return short;
          }
        }
        return path;
      } finally {
        calloc.free(src);
        calloc.free(out);
      }
    } catch (_) {
      return path;
    }
  }

  String _deviceType(String path) =>
      path.toLowerCase().endsWith('.wav') ? 'waveaudio' : 'mpegvideo';

  /// 播放一个本地文件，播完（或被打断）后返回。
  Future<void> playFile(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw const TtsPlaybackException('音频文件不存在');
    }
    final String target = _asciiPath(file.absolute.path);
    _send('close $_alias');
    final int openRc =
        _send('open "$target" type ${_deviceType(target)} alias $_alias');
    if (openRc != 0) {
      throw TtsPlaybackException('MCI open 失败（code $openRc）');
    }
    try {
      final int playRc = _send('play $_alias');
      if (playRc != 0) {
        throw TtsPlaybackException('MCI play 失败（code $playRc）');
      }
      final int lengthMs = int.tryParse(_query('status $_alias length')) ?? 0;
      final int budgetMs = (lengthMs > 0 ? lengthMs : 120000) + 8000;
      final Stopwatch watch = Stopwatch()..start();
      int emptyReads = 0;
      while (watch.elapsedMilliseconds < budgetMs) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final String mode = _query('status $_alias mode');
        if (mode.isEmpty) {
          // 刚起播时会短暂读不到状态，连续读不到才认为已结束。
          emptyReads++;
          if (emptyReads > 12) break;
          continue;
        }
        emptyReads = 0;
        if (mode != 'playing' && mode != 'seeking') break;
      }
    } finally {
      _send('close $_alias');
    }
  }

  Future<void> stop() async {
    _send('stop $_alias');
    _send('close $_alias');
  }
}

class TtsPlaybackException implements Exception {
  const TtsPlaybackException(this.message);

  final String message;

  @override
  String toString() => 'TtsPlaybackException: $message';
}
