import 'dart:io';
import 'dart:typed_data';

import 'package:dna/services/tts/ort_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';

void main() {
  test('gpt run 标准创建输入', () {
    const String modelsDir = 'd:/duetnurturingally/dna-client/modelwksps/models';
    final Float32List emb =
        File('$modelsDir/../_code_emb.bin').readAsBytesSync().buffer.asFloat32List();
    final Float32List attn =
        File('$modelsDir/../_code_attn.bin').readAsBytesSync().buffer.asFloat32List();
    final Int64List pos =
        File('$modelsDir/../_code_pos.bin').readAsBytesSync().buffer.asInt64List();
    final Float32List pyHidden =
        File('$modelsDir/../_code_hidden.bin').readAsBytesSync().buffer.asFloat32List();

    final int t = emb.length ~/ 768;
    final OrtEngine ort = OrtEngine(threads: 2);
    final OrtSessionWrapper gpt = ort.gpt(modelsDir);

    final Map<String, Float32List> floatInputs = <String, Float32List>{
      'inputs_embeds': emb,
      'attention_mask': attn,
    };
    final Map<String, Int64List> intInputs = <String, Int64List>{
      'position_ids': pos,
    };
    final Map<String, List<int>> shapes = <String, List<int>>{
      'inputs_embeds': <int>[1, t, 768],
      'attention_mask': <int>[1, attn.length],
      'position_ids': <int>[1, t],
    };
    // 标准创建：空 KV cache（0 长度 past）。
    for (int i = 0; i < 20; i++) {
      floatInputs['past.${2 * i}.k'] = Float32List(0);
      shapes['past.${2 * i}.k'] = <int>[1, 12, 0, 64];
      floatInputs['past.${2 * i + 1}.v'] = Float32List(0);
      shapes['past.${2 * i + 1}.v'] = <int>[1, 12, 0, 64];
    }

    final List<String> outNames = <String>['hidden'];
    for (int i = 0; i < 20; i++) {
      outNames.add('present.$i.k');
      outNames.add('present.$i.v');
    }

    final List<OrtValue> raw =
        gpt.run(floatInputs, intInputs, shapes, outputNames: outNames);
    final Float32List hidden = gpt.readFloatTensor(raw[0]);

    double maxDiff = 0;
    for (int i = 0; i < pyHidden.length; i++) {
      final double d = (hidden[i] - pyHidden[i]).abs();
      if (d > maxDiff) maxDiff = d;
    }
    // ignore: avoid_print
    print('dart hidden0=${hidden.take(6).toList()}');
    // ignore: avoid_print
    print('py   hidden0=${pyHidden.take(6).toList()}');
    // ignore: avoid_print
    print('maxDiff=$maxDiff');
    expect(maxDiff, lessThan(1e-3));
  });
}
