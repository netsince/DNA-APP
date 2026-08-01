import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'chattts_engine.dart';
import 'tts_config.dart';

/// 端侧语音合成服务。
///
/// 职责：
/// - 按需下载 ChatTTS ONNX 模型（ModelScope，流式写临时文件，断点续传友好）
/// - 懒加载引擎（首次合成时才加载）
/// - seed 选择：角色固定 seed + 全局兜底（effectiveSeed = roleSeed ?? globalSeed）
/// - 合成结果为 24kHz 单声道 float 音频
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  ChatTtsEngine? _engine;
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
    void Function(int done, int total)? onProgress,
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
        await _download(dir, file);
        done++;
        onProgress?.call(done, kTtsModelFiles.length);
      }
    } finally {
      _downloading = false;
    }
  }

  Future<void> _download(String dir, String file) async {
    final Uri url = Uri.parse('$kTtsModelBaseUrl/$file');
    final File tmp = File(path.join(dir, '.$file.part'));
    final File dest = File(path.join(dir, file));
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
        final IOSink sink = tmp.openWrite();
        await for (final List<int> chunk in resp.stream) {
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
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

  /// 加载引擎（懒加载）。需要模型已下载 + 内置 speaker 资产。
  Future<ChatTtsEngine> _engineLazy() async {
    if (_engine != null) return _engine!;
    final String dir = await _resolveModelsDir();
    final String asset = await rootBundle.loadString('assets/tts/tts_speaker.json');
    final Map<String, dynamic> speakerJson =
        jsonDecode(asset) as Map<String, dynamic>;
    _engine = ChatTtsEngine(
      modelsDir: dir,
      tokenizerJsonPath: path.join(dir, 'tokenizer/tokenizer.json'),
      speakerJson: speakerJson,
    );
    return _engine!;
  }

  /// 合成文本。seed 选择：角色固定 seed 优先，否则用全局 seed。
  ///
  /// 返回 24kHz 单声道 float 音频。未下载模型时抛 [StateError]。
  Future<Float32List> synthesize(
    String text, {
    int? roleSeed,
    int? globalSeed,
    bool doRefine = true,
  }) async {
    if (!await isModelsReady()) {
      throw StateError('TTS 模型尚未就绪，请先在设置中下载');
    }
    final int? seed = roleSeed ?? globalSeed;
    final ChatTtsEngine engine = await _engineLazy();
    // 同步推理较耗时；UI 接线时在按钮侧用 async + 禁用态避免阻塞体验。
    return engine.synthesize(text, seed: seed, doRefine: doRefine);
  }

  /// 释放引擎与模型会话（释放内存）。
  void releaseEngine() {
    _engine?.dispose();
    _engine = null;
  }
}
