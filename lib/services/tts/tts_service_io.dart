import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'chattts_engine.dart';
import 'tts_audio_cache.dart';
import 'tts_config.dart';
import 'tts_text_cleaner.dart';

/// 端侧语音合成服务。
///
/// 职责：
/// - 按需下载 ChatTTS ONNX 模型（ModelScope，流式写临时文件，断点续传友好）
/// - 懒加载引擎（首次合成时才加载）
/// - seed 选择：角色固定 seed + 全局兜底（effectiveSeed = roleSeed ?? globalSeed）
/// - 合成结果为 24kHz 单声道 float 音频
///
/// 仅支持 IO 平台（Android/iOS/桌面）。Web 上由 [TtsService]（stub）
/// 提供空实现，语音合成置灰禁用。
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  bool _downloading = false;

  String? get modelsDir => _modelsDir;
  String? _modelsDir;

  /// 应用文档目录下模型根目录。
  Future<String> _resolveModelsDir() async {
    if (_modelsDir != null) return _modelsDir!;
    final Directory docDir = await getApplicationDocumentsDirectory();
    _modelsDir = path.join(docDir.path, kTtsModelDirName);
    return _modelsDir!;
  }

  bool _fileExists(String dir, String file) {
    final File f = File(path.join(dir, file));
    return f.existsSync() && f.lengthSync() > 0;
  }

  /// 检查模型是否已全部下载就绪。
  Future<bool> isModelsReady() async {
    final String dir = await _resolveModelsDir();
    for (final String file in kTtsModelFiles) {
      if (!_fileExists(dir, file)) return false;
    }
    return true;
  }

  /// 只下载缺失的模型文件。
  Future<void> ensureModels({
    void Function(TtsDownloadProgress)? onProgress,
  }) async {
    if (_downloading) return;
    _downloading = true;
    try {
      final String dir = await _resolveModelsDir();
      await Directory(dir).create(recursive: true);
      int done = 0;
      for (final String file in kTtsModelFiles) {
        if (_fileExists(dir, file)) {
          done++;
          continue;
        }
        await _download(dir, file, (int recv, int? total, double? speed) {
          onProgress?.call(TtsDownloadProgress(
            doneFiles: done,
            totalFiles: kTtsModelFiles.length,
            currentFile: file,
            receivedBytes: recv,
            totalBytes: total,
            speedBps: speed,
          ));
        });
        done++;
      }
    } finally {
      _downloading = false;
    }
  }

  Future<void> _download(
    String dir,
    String file,
    void Function(int received, int? total, double? speed)? onByte,
  ) async {
    final Uri url = Uri.parse('$kTtsModelBaseUrl/$file');
    final File tmp = File(path.join(dir, '.$file.part'));
    final File dest = File(path.join(dir, file));
    // 子目录文件（如 tokenizer/tokenizer.json）的临时文件父目录（.tokenizer/）也要建。
    await tmp.parent.create(recursive: true);
    await dest.parent.create(recursive: true);
    try {
      final http.Client client = http.Client();
      try {
        final http.StreamedResponse resp =
            await client.send(http.Request('GET', url)).timeout(
                  const Duration(seconds: 60),
                  onTimeout: () => throw const SocketException('连接超时'),
                );
        if (resp.statusCode != 200) {
          throw HttpException('下载失败 HTTP ${resp.statusCode}');
        }
        final int? total = resp.contentLength;
        int received = 0;
        int lastReceived = 0;
        DateTime lastStamp = DateTime.now();
        final IOSink sink = tmp.openWrite();
        await for (final List<int> chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          final DateTime now = DateTime.now();
          if (now.difference(lastStamp).inMilliseconds >= 250) {
            final double dtSec = now.difference(lastStamp).inMilliseconds / 1000;
            final double speed = (received - lastReceived) / dtSec;
            onByte?.call(received, total, speed);
            lastReceived = received;
            lastStamp = now;
          }
        }
        await sink.flush();
        await sink.close();
        onByte?.call(received, total, null);
      } finally {
        client.close();
      }
      if (await tmp.exists()) {
        await tmp.rename(dest.path);
      }
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// 合成文本。seed 选择：角色固定 seed 优先，否则用全局 seed。
  ///
  /// 返回 24kHz 单声道 float 音频。未下载模型时抛 [StateError]。
  /// 相同（文本 + seed + 参数）会命中缓存，不重复合成。
  ///
  /// 合成在后台 isolate 执行，避免阻塞 UI 线程（onnxruntime 同步推理较重）。
  Future<Float32List> synthesize(
    String text, {
    int? roleSeed,
    int? globalSeed,
    bool doRefine = true,
    bool useCache = true,
    bool quoteOnly = true,
    void Function(double progress)? onProgress,
  }) async {
    // 全局 seed 未设置时兜底用 1（保证音色稳定，不再每次随机）。
    final int seed = roleSeed ?? globalSeed ?? 1;
    // 合成前清理：永远排除括号内容；quoteOnly 时优先只读引号内容。
    final String clean = cleanTtsText(text, quoteOnly: quoteOnly);
    final String key = TtsAudioCache.instance.keyFor(
      text: clean,
      seed: seed,
      doRefine: doRefine,
    );
    if (useCache) {
      final Float32List? cached = await TtsAudioCache.instance.load(key);
      if (cached != null) {
        onProgress?.call(1.0);
        return cached;
      }
    }
    if (!await isModelsReady()) {
      throw StateError('TTS 模型尚未就绪，请先在设置中下载');
    }
    final String dir = await _resolveModelsDir();
    final String speakerJsonString =
        await rootBundle.loadString('assets/tts/tts_speaker.json');
    final Float32List wav = await _synthInIsolate(
      modelsDir: dir,
      tokenizerJsonPath: path.join(dir, 'tokenizer/tokenizer.json'),
      speakerJsonString: speakerJsonString,
      text: clean,
      seed: seed,
      doRefine: doRefine,
      onProgress: onProgress,
    );
    if (useCache) {
      await TtsAudioCache.instance.save(key, wav);
    }
    return wav;
  }

  /// 删除已下载的全部模型文件。
  Future<void> deleteModels() async {
    final String dir = await _resolveModelsDir();
    final Directory d = Directory(dir);
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
  }
}

/// 在后台 isolate 中合成，返回音频。进度通过 SendPort 实时回传主 isolate。
Future<Float32List> _synthInIsolate({
  required String modelsDir,
  required String tokenizerJsonPath,
  required String speakerJsonString,
  required String text,
  required int? seed,
  required bool doRefine,
  void Function(double)? onProgress,
}) async {
  final ReceivePort port = ReceivePort();
  await Isolate.spawn(
    _isolateSynth,
    _IsolateArgs(
      modelsDir: modelsDir,
      tokenizerJsonPath: tokenizerJsonPath,
      speakerJsonString: speakerJsonString,
      text: text,
      seed: seed,
      doRefine: doRefine,
      port: port.sendPort,
    ),
  );
  Float32List? result;
  Object? error;
  await for (final Object msg in port) {
    if (msg is List && msg.isNotEmpty) {
      final String kind = msg[0] as String;
      if (kind == 'progress') {
        onProgress?.call(msg[1] as double);
      } else if (kind == 'done') {
        result = msg[1] as Float32List;
        break;
      } else if (kind == 'error') {
        error = msg[1] as Object;
        break;
      }
    }
  }
  port.close();
  if (error != null) {
    throw error is Exception ? error : StateError('$error');
  }
  return result!;
}

class _IsolateArgs {
  const _IsolateArgs({
    required this.modelsDir,
    required this.tokenizerJsonPath,
    required this.speakerJsonString,
    required this.text,
    required this.seed,
    required this.doRefine,
    required this.port,
  });

  final String modelsDir;
  final String tokenizerJsonPath;
  final String speakerJsonString;
  final String text;
  final int? seed;
  final bool doRefine;
  final SendPort port;
}

/// isolate 入口：创建引擎并合成，进度/结果/错误通过 port 回传。
Future<void> _isolateSynth(_IsolateArgs args) async {
  try {
    final Map<String, dynamic> speakerJson =
        jsonDecode(args.speakerJsonString) as Map<String, dynamic>;
    final ChatTtsEngine engine = ChatTtsEngine(
      modelsDir: args.modelsDir,
      tokenizerJsonPath: args.tokenizerJsonPath,
      speakerJson: speakerJson,
    );
    final Float32List wav = engine.synthesize(
      args.text,
      seed: args.seed,
      doRefine: args.doRefine,
      onProgress: (double p) => args.port.send(<Object>['progress', p]),
    );
    engine.dispose();
    args.port.send(<Object>['done', wav]);
  } catch (e, st) {
    args.port.send(<Object>['error', '$e\n$st']);
  }
}

/// 模型下载进度：当前文件字节进度 + 文件序号 + 速度。
class TtsDownloadProgress {
  const TtsDownloadProgress({
    required this.doneFiles,
    required this.totalFiles,
    required this.currentFile,
    required this.receivedBytes,
    this.totalBytes,
    this.speedBps,
  });

  final int doneFiles;
  final int totalFiles;
  final String currentFile;
  final int receivedBytes;
  final int? totalBytes;
  final double? speedBps;
}
