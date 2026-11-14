import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 离线语音转文字服务（桌面 / 移动端实现）。
///
/// 录音走 `record` 的 PCM16 流（16kHz 单声道），识别走 sherpa-onnx 的
/// 流式 OnlineRecognizer：每来一帧就 acceptWaveform + decode，把中间结果
/// 通过 [partial] 抛给 UI，检测到断句（endpoint）时把当前句并入最终文本并
/// 复位解码流，从而支持「一次录音说多句」。
///
/// 模型由 [SherpaModelDownloadService] 下载到应用文档目录，本类只负责在
/// 该目录里找出 encoder/decoder/joiner/tokens 并加载。
class SpeechToTextService {
  SpeechToTextService._();

  static final SpeechToTextService instance = SpeechToTextService._();

  /// 采样率（与 sherpa 模型的 featConfig 保持一致）。
  static const int sampleRate = 16000;

  final StreamController<String> _partialCtrl =
      StreamController<String>.broadcast();
  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  String? _loadedModelDir;

  StreamSubscription<Uint8List>? _sub;
  bool _recording = false;
  bool _bindingReady = false;

  /// 当前这句话的中间结果（用于比较是否变化）。
  String _utterancePartial = '';

  /// 已经断句确认的文本。
  String _committedText = '';

  /// 实时中间识别结果流。
  Stream<String> get partial => _partialCtrl.stream;

  bool get isRecording => _recording;

  bool get isInitialized => _recognizer != null;

  /// 加载（或复用）[modelDir] 下的识别模型。重复调用同一目录不会重复加载。
  Future<void> ensureInitialized(String modelDir) async {
    if (_recognizer != null && _loadedModelDir == modelDir) {
      return;
    }
    await _disposeRecognizer();

    _ensureBindings();
    final sherpa.OnlineRecognizerConfig config = _buildConfig(modelDir);
    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _loadedModelDir = modelDir;
  }

  /// 开始录音。返回 false 表示没有麦克风权限或设备不可用。
  Future<bool> start() async {
    if (_recording) {
      return true;
    }
    final sherpa.OnlineRecognizer? recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError('语音模型尚未加载');
    }
    // 复用旧的解码流（首次则为新建），保证 stream 与当前 recognizer 匹配。
    _stream ??= recognizer.createStream();
    _utterancePartial = '';
    _committedText = '';

    bool granted;
    try {
      granted = await _recorder.hasPermission();
    } catch (_) {
      granted = false;
    }
    if (!granted) {
      return false;
    }

    final Stream<Uint8List> audio = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
      ),
    );
    _sub = audio.listen(
      _onAudio,
      onError: (Object _) {
        // 采集出错时停止录音，避免 UI 卡在「聆听中」。
        _recording = false;
      },
      cancelOnError: false,
    );
    _recording = true;
    return true;
  }

  /// 停止录音并返回整段识别文本（含已断句的部分）。
  Future<String> stop() async {
    if (!_recording) {
      return _committedText;
    }
    _recording = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 采集已被系统断开时 stop 可能抛错，忽略即可。
    }

    final sherpa.OnlineRecognizer? recognizer = _recognizer;
    final sherpa.OnlineStream? stream = _stream;
    if (recognizer != null && stream != null) {
      // 补一段静音，让最后一个字也能进入解码窗口。
      stream.acceptWaveform(
        samples: Float32List(sampleRate ~/ 2),
        sampleRate: sampleRate,
      );
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      _appendPartial(recognizer.getResult(stream).text, emit: false);
      recognizer.reset(stream);
    }
    _utterancePartial = '';
    final String text = _committedText.trim();
    _committedText = '';
    return text;
  }

  /// 放弃本次录音（不返回文本）。
  Future<void> cancel() async {
    _recording = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 同上：设备已释放时忽略。
    }
    final sherpa.OnlineRecognizer? recognizer = _recognizer;
    final sherpa.OnlineStream? stream = _stream;
    if (recognizer != null && stream != null) {
      recognizer.reset(stream);
    }
    _utterancePartial = '';
    _committedText = '';
  }

  void dispose() {
    unawaited(cancel());
    unawaited(_disposeRecognizer());
    unawaited(_recorder.dispose());
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  void _onAudio(Uint8List bytes) {
    final sherpa.OnlineRecognizer? recognizer = _recognizer;
    final sherpa.OnlineStream? stream = _stream;
    if (recognizer == null || stream == null || bytes.isEmpty) {
      return;
    }
    stream.acceptWaveform(
      samples: convertBytesToFloat32(bytes),
      sampleRate: sampleRate,
    );
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    _appendPartial(recognizer.getResult(stream).text, emit: true);

    if (recognizer.isEndpoint(stream)) {
      _appendPartial(recognizer.getResult(stream).text, emit: false);
      recognizer.reset(stream);
      _utterancePartial = '';
    }
  }

  /// 把 [raw] 并入结果：中间结果实时抛给 UI，断句时落到 [_committedText]。
  void _appendPartial(String raw, {required bool emit}) {
    final String text = raw.trim();
    if (text.isEmpty || text == _utterancePartial) {
      return;
    }
    _utterancePartial = text;
    if (emit && !_partialCtrl.isClosed) {
      _partialCtrl.add(text);
    }
  }

  void _ensureBindings() {
    if (_bindingReady) {
      return;
    }
    if (Platform.isWindows) {
      // Flutter 桌面端无法从 package URI 解析原生库位置，直接用 exe 所在目录。
      final String exeDir = p.dirname(Platform.resolvedExecutable);
      final File dll = File(p.join(exeDir, 'sherpa-onnx-c-api.dll'));
      if (!dll.existsSync()) {
        throw StateError('缺少语音识别运行库 sherpa-onnx-c-api.dll（应在 $exeDir）');
      }
      // 必须在 c-api 之前按**完整路径**把 onnxruntime.dll 装进进程：否则 Windows
      // 会先命中 C:\Windows\System32 里的旧版 ORT（1.17 / API 17），而 sherpa 是按
      // ORT API 28 编译的，创建识别器时会直接崩（0xC0000005）。
      final File ort = File(p.join(exeDir, 'onnxruntime.dll'));
      if (ort.existsSync()) {
        DynamicLibrary.open(ort.path);
      }
      sherpa.initBindings(exeDir);
    } else {
      sherpa.initBindings();
    }
    _bindingReady = true;
  }

  sherpa.OnlineRecognizerConfig _buildConfig(String modelDir) {
    final Directory dir = Directory(modelDir);
    if (!dir.existsSync()) {
      throw StateError('语音模型目录不存在：$modelDir');
    }
    final List<File> onnx = <File>[];
    File? tokens;
    for (final FileSystemEntity entity
        in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final String name = p.basename(entity.path).toLowerCase();
      if (name == 'tokens.txt') {
        tokens = entity;
      } else if (name.endsWith('.onnx')) {
        onnx.add(entity);
      }
    }
    if (tokens == null) {
      throw StateError('语音模型缺少 tokens.txt：$modelDir');
    }

    File? encoder;
    File? decoder;
    File? joiner;
    // 同一模型常同时带 fp32 与 int8 两套 .onnx，混用（例如 int8 encoder + fp32
    // decoder）会让 onnxruntime 直接崩，所以必须先按「整套」挑：
    // 优先 int8（体积小、手机快），这套凑不齐再退回 fp32。
    for (final bool wantInt8 in <bool>[true, false]) {
      File? e;
      File? d;
      File? j;
      for (final File file in onnx) {
        final String name = p.basename(file.path).toLowerCase();
        final bool isInt8 = name.contains('.int8.');
        if (isInt8 != wantInt8) {
          continue;
        }
        if (name.contains('encoder')) {
          e ??= file;
        } else if (name.contains('decoder')) {
          d ??= file;
        } else if (name.contains('joiner')) {
          j ??= file;
        }
      }
      // transducer 需要三件套齐全；paraformer 只有 encoder+decoder。
      final bool para = modelDir.toLowerCase().contains('paraformer');
      if (e != null && d != null && (para || j != null)) {
        encoder = e;
        decoder = d;
        joiner = j;
        break;
      }
    }
    if (encoder == null || decoder == null) {
      throw StateError('语音模型缺少 encoder/decoder：$modelDir');
    }

    final bool isParaformer = modelDir.toLowerCase().contains('paraformer');
    final sherpa.OnlineModelConfig model = sherpa.OnlineModelConfig(
      transducer: joiner == null || isParaformer
          ? const sherpa.OnlineTransducerModelConfig()
          : sherpa.OnlineTransducerModelConfig(
              encoder: encoder.path,
              decoder: decoder.path,
              joiner: joiner.path,
            ),
      paraformer: isParaformer
          ? sherpa.OnlineParaformerModelConfig(
              encoder: encoder.path,
              decoder: decoder.path,
            )
          : const sherpa.OnlineParaformerModelConfig(),
      tokens: tokens.path,
      numThreads: 2,
      debug: false,
      modelType: isParaformer ? 'paraformer' : 'zipformer',
    );

    return sherpa.OnlineRecognizerConfig(
      model: model,
      feat: const sherpa.FeatureConfig(sampleRate: sampleRate, featureDim: 80),
      decodingMethod: 'greedy_search',
      enableEndpoint: true,
      // 断句阈值：静音 0.8s 结束一句（默认为 1.2s，语音输入手感更慢）。
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 0.8,
      rule3MinUtteranceLength: 20,
    );
  }

  Future<void> _disposeRecognizer() async {
    _recognizer?.free();
    _recognizer = null;
    _stream = null;
    _loadedModelDir = null;
  }
}

/// 将 16-bit PCM 字节（小端）转换为 Float32 采样（[-1, 1]）。
Float32List convertBytesToFloat32(Uint8List bytes) {
  final ByteData byteData = ByteData.sublistView(bytes);
  final int length = bytes.length ~/ 2;
  final Float32List float32 = Float32List(length);
  for (int i = 0; i < length; i++) {
    float32[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return float32;
}
