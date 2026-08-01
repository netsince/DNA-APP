import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dna/services/tts/chattts_engine.dart';

void main() {
  test('端到端合成（GPT→DVAE→Vocos→istft）', () {
    final Map<String, dynamic> speakerJson = jsonDecode(
          File(r'D:\duetnurturingally\dna-client\modelwksps\tts_speaker.json')
              .readAsStringSync(),
        )
        as Map<String, dynamic>;
    final ChatTtsEngine engine = ChatTtsEngine(
      modelsDir: r'D:\duetnurturingally\dna-client\modelwksps\models',
      tokenizerJsonPath:
          r'D:\duetnurturingally\dna-client\modelwksps\models\tokenizer\tokenizer.json',
      speakerJson: speakerJson,
      threads: 4,
    );
    // 简短文本 + 关 refine + 限 code 长度，做快速冒烟验证
    final Float32List wav =
        engine.synthesize('你好', seed: 42, doRefine: false, maxNewCode: 128);
    expect(wav.length, greaterThan(0));
    // 计算能量，确认非静音
    double energy = 0;
    for (final double x in wav) {
      energy += x * x;
    }
    final double rms = math.sqrt(energy / wav.length);
    // ignore: avoid_print
    print('合成长度=${wav.length} samples (${wav.length / 24000}s) RMS=$rms');
    expect(rms, greaterThan(1e-4));
    engine.dispose();
  });
}
