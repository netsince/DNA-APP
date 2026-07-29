import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../models/voice_models.dart';

/// 离线语音转文字服务（sherpa-onnx + record）。
///
/// 采用「按住说话」模式：调用 [start] 开始录音并流式识别，[stop] 结束并返回最终文本，
/// 识别过程中的中间结果通过 [partial] 流实时广播，供输入框即时显示。
///
/// 识别器较重，[ensureInitialized] 只在首次使用时构建一次；[modelDir] 指向
/// 由 [SherpaModelDownloadService] 解压出的模型目录。
class SpeechToTextService {
  SpeechToTextService._();

  static final SpeechToTextService instance = SpeechToTextService._();

  final AudioRecorder _recorder = AudioRecorder();
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _recordSub;
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _isRecording = false;

  /// 采样率（sherpa-onnx 要求 16000Hz 单声道）。
  static const int sampleRate = 16000;

  /// 实时中间识别结果流。
  Stream<String> get partial => _partialController.stream;

  bool get isRecording => _isRecording;

  bool get isInitialized => _initialized;

  /// 初始化识别器（仅首次构建）。[modelDir] 为模型目录。
  Future<void> ensureInitialized(String modelDir) async {
    if (_initialized) {
      return;
    }
    sherpa_onnx.initBindings();
    final sherpa_onnx.OnlineRecognizerConfig config =
        await _buildConfig(modelDir);
    _recognizer = sherpa_onnx.OnlineRecognizer(config);
    _initialized = true;
  }

  /// 开始录音与流式识别。返回是否成功开始（无权限或未初始化时返回 false）。
  Future<bool> start() async {
    if (_recognizer == null || _isRecording) {
      return false;
    }
    if (!await _recorder.hasPermission()) {
      return false;
    }

    _stream?.free();
    _stream = _recognizer!.createStream();
    _partialController.add('');

    final Stream<Uint8List> audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _recordSub = audioStream.listen((Uint8List data) {
      if (!_isRecording || _stream == null) {
        return;
      }
      final Float32List samples = convertBytesToFloat32(data);
      _stream!.acceptWaveform(samples: samples, sampleRate: sampleRate);
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      final String text = _recognizer!.getResult(_stream!).text;
      if (text.isNotEmpty) {
        _partialController.add(text);
      }
      // 不在端点处 reset：连续听写时保留已识别内容，避免停顿导致文字被清空。
    });

    _isRecording = true;
    return true;
  }

  /// 停止录音并返回最终识别文本（已 trim）。
  Future<String> stop() async {
    if (!_isRecording) {
      return '';
    }
    await _recordSub?.cancel();
    _recordSub = null;
    await _recorder.stop();

    final String text =
        _stream == null ? '' : _recognizer!.getResult(_stream!).text;
    _stream?.free();
    _stream = null;
    _isRecording = false;
    return text.trim();
  }

  /// 停止录音但不返回/发送结果（取消本次输入）。
  Future<void> cancel() async {
    if (!_isRecording) {
      return;
    }
    await _recordSub?.cancel();
    _recordSub = null;
    await _recorder.stop();
    _stream?.free();
    _stream = null;
    _isRecording = false;
  }

  /// 释放识别器与资源（一般用于退出应用，可选）。
  void dispose() {
    _recordSub?.cancel();
    _stream?.free();
    _recognizer?.free();
    _recognizer = null;
    _stream = null;
    _initialized = false;
  }

  /// 在模型目录中自动定位 encoder/decoder/joiner/tokens，构建识别器配置。
  Future<sherpa_onnx.OnlineRecognizerConfig> _buildConfig(
      String modelDir) async {
    final Directory dir = Directory(modelDir);
    final List<FileSystemEntity> entries =
        await dir.list(recursive: true, followLinks: false).toList();

    String? tokens;
    String? encoder;
    String? decoder;
    String? joiner;

    for (final FileSystemEntity entity in entries) {
      if (entity is! File) {
        continue;
      }
      final String name = path.basename(entity.path).toLowerCase();
      if (name == 'tokens.txt') {
        tokens ??= entity.path;
      } else if (name.endsWith('.onnx')) {
        if (name.startsWith('encoder')) {
          if (encoder == null || name.contains('int8')) {
            encoder = entity.path;
          }
        } else if (name.startsWith('decoder')) {
          if (decoder == null || name.contains('int8')) {
            decoder = entity.path;
          }
        } else if (name.startsWith('joiner')) {
          if (joiner == null || name.contains('int8')) {
            joiner = entity.path;
          }
        }
      }
    }

    if (tokens == null ||
        encoder == null ||
        decoder == null ||
        joiner == null) {
      throw Exception('模型文件不完整，无法初始化离线识别器。');
    }

    String modelType = 'zipformer';
    if (encoder.contains('chunk-')) {
      modelType = 'zipformer2';
    }

    return sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: encoder,
          decoder: decoder,
          joiner: joiner,
        ),
        tokens: tokens,
        modelType: modelType,
      ),
      ruleFsts: '',
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
