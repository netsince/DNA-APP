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

    final OrtRunOptions runOpts = OrtRunOptions();
    // 标准创建：OrtValue.createTensor
    final Map<String, OrtValue> feeds = <String, OrtValue>{
      'inputs_embeds': OrtValue.createTensor(emb, <int>[1, t, 768]),
      'attention_mask': OrtValue.createTensor(attn, <int>[1, attn.length]),
      'position_ids': OrtValue.createTensor(pos, <int>[1, t]),
    };
    for (int i = 0; i < 20; i++) {
      feeds['past.${2 * i}.k'] = OrtValue.createTensor(Float32List(0), <int>[1, 12, 0, 64]);
      feeds['past.${2 * i + 1}.v'] = OrtValue.createTensor(Float32List(0), <int>[1, 12, 0, 64]);
    }
    final List<String> outNames = <String>['hidden'];
    for (int i = 0; i < 40; i++) {
      outNames.add('present.$i.${i.isEven ? 'k' : 'v'}');
    }
    final raw = gpt.session.run(runOpts, feeds, outNames);
    final Float32List hidden = gpt.readFloatTensor(raw![0]!);
    for (final OrtValue v in feeds.values) {
      v.release();
    }
    runOpts.release();

    double maxDiff = 0;
    for (int i = 0; i < pyHidden.length; i++) {
      final double d = (hidden[i] - pyHidden[i]).abs();
      if (d > maxDiff) maxDiff = d;
    }
    // ignore: avoid_print
    print('dart hidden0=${hidden.take(6).toList()}');
    print('py   hidden0=${pyHidden.take(6).toList()}');
    print('maxDiff=$maxDiff');
    expect(maxDiff, lessThan(1e-3));
  });
}
