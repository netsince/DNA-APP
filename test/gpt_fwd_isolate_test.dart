import 'dart:io';
import 'dart:typed_data';

import 'package:dna/services/tts/chattts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gpt_forward 首步隔离测试', () {
    const String modelsDir = 'd:/duetnurturingally/dna-client/modelwksps/models';
    final Uint8List embRaw =
        File('$modelsDir/../_code_emb.bin').readAsBytesSync();
    final Float32List emb = embRaw.buffer.asFloat32List();
    final Uint8List attnRaw =
        File('$modelsDir/../_code_attn.bin').readAsBytesSync();
    final Float32List attn = attnRaw.buffer.asFloat32List();
    final Uint8List posRaw =
        File('$modelsDir/../_code_pos.bin').readAsBytesSync();
    final Int64List pos = posRaw.buffer.asInt64List();
    final Uint8List hidRaw =
        File('$modelsDir/../_code_hidden.bin').readAsBytesSync();
    final Float32List pyHidden = hidRaw.buffer.asFloat32List();

    final int t = emb.length ~/ 768;
    // ignore: avoid_print
    print('emb len=${emb.length} t=$t attn=${attn.length} pos=${pos.length}');

    // 需要构造一个 ChatTtsEngine 实例来访问 _gptForward（私有方法不可访问）
    // 改用 OrtEngine 直接跑，或反射。这里用外部访问方式。
    // 由于 _gptForward 是私有，改用直接通过引擎合成对比。
    // 简化：直接跑完整 synthesize，看 hidden 是否匹配。
  });
}
