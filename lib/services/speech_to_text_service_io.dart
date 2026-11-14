import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../models/voice_models.dart';
import 'stt_transcript.dart';
import 'bgm_player.dart';

/// 离线语音转文字服务（sherpa-onnx + record）。
///
/// 采用「按住说话」模式：[start] 开始录音并流式识别，[stop] 结束并返回整段文本，
/// 识别过程中的中间结果通过 [partial] 流实时广播，供输入框即时显示。
///
/// **断句策略**：识别器开启 endpoint，检测到断句就把当前句并入 [_committedText]
/// 并复位解码流，[partial] 始终广播「已确认文本 + 当前句」。这样做的原因是
/// 解码流的上下文会一直累积：长段听写不切句时，识别器容易把前文重复解码出来，
/// 表现为越说越乱。切句后每句都是独立的解码窗口。
///
/// 识别器较重，[ensureInitialized] 按模型目录缓存；[modelDir] 指向由
/// [SherpaModelDownloadService] 解压出的模型目录。
///
/// 仅支持 IO 平台（Android/iOS/桌面）。Web 上由 [SpeechToTextService]（stub）
/// 提供空实现，语音输入置灰禁用。
class SpeechToTextService {
  SpeechToTextService._();

  static final SpeechToTextService instance = SpeechToTextService._();

  /// 采样率（与 sherpa-onnx 模型的 featureConfig 一致）。
  static const int sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _recordSub;
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  /// 当前模型目录：同目录重复调用 [ensureInitialized] 不重复加载。
  String? _loadedModelDir;

  bool _isRecording = false;

  /// 文本累加状态机（已确认文本 + 当前句），逻辑与平台无关，见 stt_transcript.dart。
  final SttTranscript _transcript = SttTranscript();

  /// 实时中间识别结果流：内容是「已确认文本 + 当前句」。
  Stream<String> get partial => _partialController.stream;

  bool get isRecording => _isRecording;

  bool get isInitialized => _recognizer != null;

  /// 加载（或复用）[modelDir] 下的识别模型。
  Future<void> ensureInitialized(String modelDir) async {
    if (_recognizer != null && _loadedModelDir == modelDir) {
      return;
    }
    _disposeRecognizer();
    sherpa_onnx.initBindings();
    final sherpa_onnx.OnlineRecognizerConfig config = _buildConfig(modelDir);
    _recognizer = sherpa_onnx.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _loadedModelDir = modelDir;
  }

  /// 开始录音与流式识别。返回是否成功开始（无权限或未初始化时返回 false）。
  Future<bool> start() async {
    final sherpa_onnx.OnlineRecognizer? recognizer = _recognizer;
    if (recognizer == null) {
      return false;
    }
    if (_isRecording) {
      return true;
    }

    // 复用与当前 recognizer 匹配的解码流（首次则为新建）。
    _stream ??= recognizer.createStream();
    _transcript.reset();

    bool granted;
    try {
      granted = await _recorder.hasPermission();
    } catch (_) {
      granted = false;
    }
    if (!granted) {
      return false;
    }

    final Stream<Uint8List> audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // 麦克风增益与降噪：手机端远场输入明显更稳。
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
      ),
    );

    _recordSub = audioStream.listen(
      _onAudio,
      onError: (Object _) {
        // 采集出错时复位，避免 UI 卡在「聆听中」。
        _isRecording = false;
      },
      cancelOnError: false,
    );

    _isRecording = true;
    _partialController.add('');
    // 识别开始：把背景音乐音量调小，避免盖住麦克风拾取的人声。
    await BgmPlayer.instance.duck();
    return true;
  }

  /// 停止录音并返回最终识别文本（已 trim）。
  Future<String> stop() async {
    if (!_isRecording) {
      return _transcript.committed.trim();
    }
    _isRecording = false;
    await _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 设备已被系统释放时 stop 可能抛错，忽略即可。
    }

    _flushTail();
    final String text = _transcript.takeFinal();
    // 识别结束：恢复背景音乐音量。
    await BgmPlayer.instance.unduck();
    return text;
  }

  /// 停止录音但不返回/发送结果（取消本次输入）。
  Future<void> cancel() async {
    if (!_isRecording) {
      return;
    }
    _isRecording = false;
    await _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 同上。
    }
    final sherpa_onnx.OnlineRecognizer? recognizer = _recognizer;
    final sherpa_onnx.OnlineStream? stream = _stream;
    if (recognizer != null && stream != null) {
      recognizer.reset(stream);
    }
    _transcript.reset();
    // 识别取消：恢复背景音乐音量。
    await BgmPlayer.instance.unduck();
  }

  /// 释放识别器与资源（一般用于退出应用，可选）。
  void dispose() {
    _recordSub?.cancel();
    _disposeRecognizer();
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  void _onAudio(Uint8List bytes) {
    final sherpa_onnx.OnlineRecognizer? recognizer = _recognizer;
    final sherpa_onnx.OnlineStream? stream = _stream;
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
    _pushPartial(recognizer.getResult(stream).text);

    // 断句：把这一句并入已确认文本，然后复位解码流 —— 下一句重新开窗。
    if (recognizer.isEndpoint(stream)) {
      _commitPartial(recognizer.getResult(stream).text);
      recognizer.reset(stream);
    }
  }

  /// 更新当前句并把「已确认 + 当前句」推给 UI。
  void _pushPartial(String raw) {
    if (!_transcript.updateCurrentIfChanged(raw)) {
      return;
    }
    if (!_partialController.isClosed) {
      _partialController.add(_transcript.display);
    }
  }

  /// 断句提交：当前句并入已确认文本，并把结果推给 UI。
  void _commitPartial(String raw) {
    _transcript.updateCurrent(raw);
    _transcript.commitCurrent();
    if (!_partialController.isClosed) {
      _partialController.add(_transcript.display);
    }
  }

  /// 停止前补一段静音，让最后一个字进入解码窗口，然后提交收尾。
  void _flushTail() {
    final sherpa_onnx.OnlineRecognizer? recognizer = _recognizer;
    final sherpa_onnx.OnlineStream? stream = _stream;
    if (recognizer == null || stream == null) {
      return;
    }
    stream.acceptWaveform(
      samples: Float32List(sampleRate ~/ 2),
      sampleRate: sampleRate,
    );
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    _transcript.updateCurrent(recognizer.getResult(stream).text);
    _transcript.commitCurrent();
    recognizer.reset(stream);
  }

  void _disposeRecognizer() {
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    _loadedModelDir = null;
  }

  /// 在模型目录中自动定位 encoder/decoder/joiner/tokens，构建识别器配置。
  sherpa_onnx.OnlineRecognizerConfig _buildConfig(String modelDir) {
    final Directory dir = Directory(modelDir);
    if (!dir.existsSync()) {
      throw StateError('语音模型目录不存在：$modelDir');
    }

    final List<File> onnxFiles = <File>[];
    File? tokens;
    for (final FileSystemEntity entity
        in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final String name = path.basename(entity.path).toLowerCase();
      if (name == 'tokens.txt') {
        tokens = entity;
      } else if (name.endsWith('.onnx')) {
        onnxFiles.add(entity);
      }
    }
    if (tokens == null) {
      throw StateError('语音模型缺少 tokens.txt：$modelDir');
    }

    File? encoder;
    File? decoder;
    File? joiner;
    // 同一模型常同时带 fp32 与 int8 两套 .onnx。混用（int8 encoder + fp32
    // decoder）会让 onnxruntime 直接崩，所以必须按「整套」挑：先试 int8，
    // 这套凑不齐再退回 fp32。
    for (final bool wantInt8 in <bool>[true, false]) {
      File? e;
      File? d;
      File? j;
      for (final File file in onnxFiles) {
        final String name = path.basename(file.path).toLowerCase();
        if (name.contains('.int8.') != wantInt8) {
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
      if (e != null && d != null && j != null) {
        encoder = e;
        decoder = d;
        joiner = j;
        break;
      }
    }
    if (encoder == null || decoder == null || joiner == null) {
      throw StateError('模型文件不完整，无法初始化离线识别器：$modelDir');
    }

    // chunk- 前缀是 zipformer2（新版流式模型），其余按 zipformer 处理。
    final String modelType = encoder.path.contains('chunk-')
        ? 'zipformer2'
        : 'zipformer';

    return sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: encoder.path,
          decoder: decoder.path,
          joiner: joiner.path,
        ),
        tokens: tokens.path,
        numThreads: 2,
        modelType: modelType,
      ),
      feat: const sherpa_onnx.FeatureConfig(
        sampleRate: sampleRate,
        featureDim: 80,
      ),
      decodingMethod: 'greedy_search',
      enableEndpoint: true,
      // 断句阈值：静音 0.8s 结束一句（默认 1.2s，说话时停顿一下就要等太久）。
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 0.8,
      rule3MinUtteranceLength: 20,
    );
  }
}

/// 将 16-bit PCM 字节（小端）转换为 sherpa-onnx 需要的 Float32 采样（范围 [-1,1]）。
Float32List convertBytesToFloat32(Uint8List bytes) {
  final ByteData byteData = ByteData.sublistView(bytes);
  final int length = bytes.length ~/ 2;
  final Float32List float32 = Float32List(length);
  for (int i = 0; i < length; i++) {
    final int intSample = byteData.getInt16(i * 2, Endian.little);
    float32[i] = intSample / 32768.0;
  }
  return float32;
}

/// 根据 id 取得对应模型选项的便捷函数（供 UI 使用）。
VoiceModelOption resolveVoiceModel(String id) => voiceModelById(id);
