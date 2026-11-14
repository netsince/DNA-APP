import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'speech_to_text_service.dart';
import 'sherpa_model_service.dart';
import '../models/voice_models.dart';

/// 启动自检：仅在设置了环境变量 DNA_STT_SELFTEST=<模型目录> 时运行。
///
/// 用途：验证打包后的应用进程里能正确装好 sherpa/onnxruntime 原生库并创建识别器
/// （这是肉眼点 UI 最难覆盖的一段），并顺带列出麦克风设备。结果写进临时目录日志。
/// 追加环境变量 DNA_STT_RECORD_SECONDS=N 时，会真的录 N 秒并打印识别文本。
class SttSelfTest {
  static Future<void> runIfRequested() async {
    if (kIsWeb || !Platform.isWindows) return;
    final String? modelDir = Platform.environment['DNA_STT_SELFTEST'];
    if (modelDir == null || modelDir.isEmpty) return;

    final Directory dir = await getTemporaryDirectory();
    final File log = File('${dir.path}/dna_stt_selftest.log');
    void w(String s) {
      try {
        log.writeAsStringSync(
          '${DateTime.now().toIso8601String()} $s\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    }

    w('start model=$modelDir');

    // 可选：先在应用内跑一遍「下载 + 解压」，验证普通用户点设置页时的真实链路。
    if (Platform.environment['DNA_STT_DOWNLOAD'] == '1') {
      try {
        final VoiceModelOption model = voiceModelById(
          Platform.environment['DNA_STT_DOWNLOAD_MODEL'] ??
              'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23',
        );
        final SherpaModelSource? source = buildSherpaSource(id: 'modelscope');
        if (source == null) {
          w('download ERROR: no source');
          return;
        }
        final SherpaDownloadResult res =
            await SherpaModelDownloadService.downloadModel(
          source: source,
          model: model,
          onProgress: (double? progress, int received, int? total, double? bps) {
            if (received % (8 << 20) < 65536) {
              w('download ${(progress ?? 0) * 100 ~/ 1}% '
                  '${received ~/ (1 << 20)}MB/${total == null ? '?' : '${total ~/ (1 << 20)}MB'}');
            }
          },
        );
        w('download success=${res.success} msg=${res.message} dir=${res.modelDir}');
      } catch (e) {
        w('download ERROR $e');
      }
    }
    try {
      await SpeechToTextService.instance.ensureInitialized(modelDir);
      w('initialized=${SpeechToTextService.instance.isInitialized}');
    } catch (e) {
      w('ERROR $e');
      return;
    }

    try {
      final List<InputDevice> devices = await AudioRecorder().listInputDevices();
      w('input devices(${devices.length}): '
          '${devices.map((InputDevice d) => '${d.label}[${d.id}]').join(' | ')}');
    } catch (e) {
      w('listInputDevices ERROR $e');
    }

    final String? secs = Platform.environment['DNA_STT_RECORD_SECONDS'];
    if (secs == null || secs.isEmpty) return;
    final int seconds = int.tryParse(secs) ?? 3;
    try {
      final bool ok = await SpeechToTextService.instance.start();
      w('record start=$ok for ${seconds}s');
      if (!ok) return;
      await Future<void>.delayed(Duration(seconds: seconds));
      final String text = await SpeechToTextService.instance.stop();
      w('FINAL "$text"');
    } catch (e) {
      w('record ERROR $e');
    }
  }
}
