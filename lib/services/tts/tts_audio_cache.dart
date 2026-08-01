import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 生成音频缓存服务：按键值去重、默认持久化到本地、可统计大小与清理。
///
/// 键由（文本 + seed + 关键参数）哈希得到；相同键不会重复合成。
class TtsAudioCache {
  TtsAudioCache._();

  static final TtsAudioCache instance = TtsAudioCache._();

  static const String _cacheDirName = 'tts_cache';

  String? _cacheDir;

  Future<String> _resolveDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final Directory doc = await getApplicationDocumentsDirectory();
    _cacheDir = path.join(doc.path, _cacheDirName);
    return _cacheDir!;
  }

  /// 由文本与合成参数计算缓存键。
  String keyFor({
    required String text,
    required int? seed,
    bool doRefine = true,
    double temperature = 0.3,
    double topP = 0.7,
    int topK = 20,
  }) {
    final String raw =
        '$text|$seed|$doRefine|$temperature|$topP|$topK';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  /// 从缓存读取音频（Float32List），不存在返回 null。
  Future<Float32List?> load(String key) async {
    final String dir = await _resolveDir();
    final File f = File(path.join(dir, '$key.f32'));
    if (!await f.exists()) return null;
    final Uint8List bytes = await f.readAsBytes();
    return Float32List.view(bytes.buffer);
  }

  /// 把音频写入缓存（持久化）。
  Future<void> save(String key, Float32List samples) async {
    final String dir = await _resolveDir();
    await Directory(dir).create(recursive: true);
    final File f = File(path.join(dir, '$key.f32'));
    await f.writeAsBytes(samples.buffer.asUint8List(), flush: true);
  }

  /// 当前缓存占用字节数。
  Future<int> totalBytes() async {
    final Directory dir = Directory(await _resolveDir());
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File) {
        total += await e.length();
      }
    }
    return total;
  }

  /// 缓存文件数量。
  Future<int> count() async {
    final Directory dir = Directory(await _resolveDir());
    if (!await dir.exists()) return 0;
    int n = 0;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File && e.path.endsWith('.f32')) n++;
    }
    return n;
  }

  /// 清空所有缓存音频文件。
  Future<void> clear() async {
    final Directory dir = Directory(await _resolveDir());
    if (!await dir.exists()) return;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File && e.path.endsWith('.f32')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }
}
