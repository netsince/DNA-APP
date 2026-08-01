import 'dart:io';
import 'dart:typed_data';

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

    final int t = emb.length ~/ 768;
    // ignore: avoid_print
    print('emb len=${emb.length} t=$t attn=${attn.length} pos=${pos.length}');

    // 由于 _gptForward 为私有方法，完整的合成对比请在集成测试中验证。
  });
}
