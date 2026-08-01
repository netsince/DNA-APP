import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dna/services/tts/tts_math.dart';

void main() {
  test('istft 与 numpy 参考一致', () {
    final Map<String, dynamic> ref = jsonDecode(
          File(r'D:\duetnurturingally\dna-client\modelwksps\istft_ref.json')
              .readAsStringSync(),
        )
        as Map<String, dynamic>;
    final List<double> real =
        (ref['real'] as List).map((dynamic x) => (x as num).toDouble()).toList();
    final List<double> imag =
        (ref['imag'] as List).map((dynamic x) => (x as num).toDouble()).toList();
    final List<double> expected =
        (ref['wav'] as List).map((dynamic x) => (x as num).toDouble()).toList();
    final int nFft = ref['n_fft'] as int;
    final int hop = ref['hop'] as int;
    final int win = ref['win'] as int;
    final int pad = ref['pad'] as int;

    final Float32List out = istft(real, imag, nFft, hop, win, pad);
    expect(out.length, expected.length);

    double maxErr = 0;
    double sumSqErr = 0;
    for (int i = 0; i < out.length; i++) {
      final double err = (out[i] - expected[i]).abs();
      if (err > maxErr) maxErr = err;
      sumSqErr += err * err;
    }
    final double rmse = math.sqrt(sumSqErr / out.length);
    // ignore: avoid_print
    print('istft 最大误差=$maxErr RMSE=$rmse');
    expect(maxErr, lessThan(5e-3));
  });
}
