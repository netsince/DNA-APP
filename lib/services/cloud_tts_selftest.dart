import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_tts_service.dart';
import 'tts/tts_player.dart';

/// 启动自检：仅在设置了环境变量 DNA_TTS_SELFTEST 时运行。
/// 用途：在不点 UI 的情况下验证「合成 → 播放」整条链路，把结果写进临时日志。
/// mode = "url"  → 直接播 HTTP 地址（旧实现，怀疑会崩）
/// mode = "file" → 先下载到临时文件再播（新实现）
class CloudTtsSelfTest {
  static Future<void> runIfRequested() async {
    if (kIsWeb) return;
    final String? mode = Platform.environment['DNA_TTS_SELFTEST'];
    if (mode == null || mode.isEmpty) return;

    final Directory dir = await getTemporaryDirectory();
    final File log = File('${dir.path}/dna_tts_selftest.log');
    void w(String s) {
      try {
        log.writeAsStringSync(
          '${DateTime.now().toIso8601String()} [$mode] $s\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    }

    w('start');
    try {
      await CloudTtsService.instance.load();
      w('enabled=${CloudTtsService.instance.enabled} base=${CloudTtsService.instance.baseUrl}');
      final CloudTtsClip clip = await CloudTtsService.instance.speak('自检：云端语音合成。');
      w('clip ok seconds=${clip.seconds} voice=${clip.voice} url=${clip.url}');
      if (mode == 'voice') {
        final String? v = Platform.environment['DNA_TTS_VOICE'];
        w('voice mode, requested=${v ?? '(auto)'}');
        final CloudTtsClip played = await CloudTtsService.instance
            .speakAndPlay('自检：可选音色。', voice: v);
        w('voice done voice=${played.voice} seconds=${played.seconds}');
      } else if (mode == 'play') {
        w('speakAndPlay begin');
        final CloudTtsClip played =
            await CloudTtsService.instance.speakAndPlay('自检：云端语音合成。');
        w('speakAndPlay done seconds=${played.seconds}');
      } else if (mode == 'url') {
        w('playUrl begin');
        await TtsPlayer.instance.playUrl(clip.url);
        w('playUrl done');
      } else {
        final String path = await CloudTtsService.instance.downloadToTemp(clip.url);
        w('downloaded bytes=${File(path).lengthSync()}');
        w('playFile begin');
        await TtsPlayer.instance.playFile(path);
        w('playFile done');
      }
    } catch (e, st) {
      w('ERROR $e\n$st');
    }
  }
}
