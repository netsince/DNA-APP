import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dna/services/tts/tts_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// ISTFT 的契约(复刻 modelwksps/chattts_onnx.py 的 `numpy_istft`)。
///
/// 约定:real/imag 是 **rfft 布局** `[bins, T]`(bin 优先),
/// `bins = n_fft/2 + 1` —— 与 numpy 的 `irfft(spec, n=n_fft, axis=1)` 对齐
/// (numpy 对 irfft 的输入长度有硬性要求,必须是 n_fft/2+1)。
///
/// 这里刻意**自带一份独立的 radix-2 FFT / rfft** 来做正变换,而不是复用
/// tts_math 里的实现 —— 复用的话两边共用一个 bug,测试就白写了。
///
/// 历史:这组测试替换掉了原先读 `modelwksps/istft_ref.json` 的版本。那份
/// 参考数据是本地生成物(该目录被 .gitignore 忽略),而且与真实约定不符
/// (它的 real/imag 是 512×20 = 10240,而 513 bins 下帧数不是整数),
/// 所以它既跑不了、也测不出真问题。
const int _nFft = 1024;
const int _hop = 256;
const int _win = 1024;

/// rfft 的 bin 数:513(含 Nyquist)。
const int _bins = _nFft ~/ 2 + 1;

Float64List _hann(int n) {
  final Float64List w = Float64List(n);
  for (int i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  return w;
}

/// 原地 radix-2 FFT([invert] 时做 IFFT,带 1/n 归一化)。
void _fft(Float64List re, Float64List im, {required bool invert}) {
  final int n = re.length;
  for (int i = 1, j = 0; i < n; i++) {
    int bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final double tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final double ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (int len = 2; len <= n; len <<= 1) {
    final double ang = 2 * math.pi / len * (invert ? 1 : -1);
    final double wr = math.cos(ang);
    final double wi = math.sin(ang);
    for (int i = 0; i < n; i += len) {
      double cr = 1;
      double ci = 0;
      for (int k = 0; k < len ~/ 2; k++) {
        final int a = i + k;
        final int b = i + k + len ~/ 2;
        final double xr = re[b] * cr - im[b] * ci;
        final double xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final double ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
  if (invert) {
    for (int i = 0; i < n; i++) {
      re[i] /= n;
      im[i] /= n;
    }
  }
}

/// 正变换:按 hop 切帧、加 hann 窗、rfft,按 [bins, T] 铺平。
({List<double> real, List<double> imag, int frames}) _stft(List<double> x) {
  final int t = (x.length - _win) ~/ _hop + 1;
  final Float64List window = _hann(_win);
  final List<double> real = List<double>.filled(_bins * t, 0);
  final List<double> imag = List<double>.filled(_bins * t, 0);
  final Float64List re = Float64List(_win);
  final Float64List im = Float64List(_win);
  for (int fi = 0; fi < t; fi++) {
    for (int i = 0; i < _win; i++) {
      re[i] = x[fi * _hop + i] * window[i];
      im[i] = 0;
    }
    _fft(re, im, invert: false);
    for (int k = 0; k < _bins; k++) {
      real[k * t + fi] = re[k];
      imag[k * t + fi] = im[k];
    }
  }
  return (real: real, imag: imag, frames: t);
}

/// 造一段长度 = (T-1)*hop + win 的测试信号。
List<double> _signal(int frames) {
  final int len = (frames - 1) * _hop + _win;
  return <double>[
    for (int i = 0; i < len; i++)
        0.5 * math.sin(2 * math.pi * 440 * i / 24000) +
        0.3 * math.sin(2 * math.pi * 1337 * i / 24000 + 0.7),
  ];
}

double _maxErr(List<double> a, Float32List b, {required int skip}) {
  double m = 0;
  for (int i = skip; i < a.length - skip && i < b.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

void main() {
  test('输出长度 = (T-1)*hop + win - 2*pad', () {
    final List<double> x = _signal(20);
    final ({List<double> real, List<double> imag, int frames}) s = _stft(x);
    expect(s.frames, 20);
    expect(s.real.length, _bins * 20);

    final Float32List out = istft(s.real, s.imag, _nFft, _hop, _win, 384);
    expect(out.length, (20 - 1) * _hop + _win - 2 * 384);
  });

  test('往返重建:正变换 → istft 应还原原信号', () {
    final List<double> x = _signal(20);
    final ({List<double> real, List<double> imag, int frames}) s = _stft(x);
    final Float32List out = istft(s.real, s.imag, _nFft, _hop, _win, 0);

    // 两端各有不到一帧的补窗不完整,比对时跳过首尾一个 hop
    expect(
      _maxErr(x, out, skip: _hop),
      lessThan(1e-4),
      reason: '加权 OLA(y/env)应精确还原原信号',
    );
  });

  test('Nyquist bin 必须参与重建(曾被错误置 0)', () {
    // 只保留 Nyquist(bin 512)的频谱:输出应是逐点反号的 Nyquist 振荡。
    final int frames = 20;
    final List<double> real = List<double>.filled(_bins * frames, 0);
    final List<double> imag = List<double>.filled(_bins * frames, 0);
    for (int fi = 0; fi < frames; fi++) {
      real[(_bins - 1) * frames + fi] = 1; // bin 512
    }

    final Float32List out = istft(real, imag, _nFft, _hop, _win, 0);
    final int mid = (frames ~/ 2) * _hop;

    // 不去断言具体幅度:WOLA 的 y/env 归一化里含窗自身的谱泄漏,
    // 单 bin 频谱的幅度不是简单的 1/n(实测是 4/3 倍 —— 汉宁窗的
    // Σw/Σw² = 512/384)。这里只钉住"Nyquist 有没有参与":
    // 被丢掉时整个输出恒为 0。
    double maxAbs = 0;
    for (int i = mid; i < mid + 256; i++) {
      maxAbs = math.max(maxAbs, out[i].abs());
    }
    expect(maxAbs, greaterThan(1e-4), reason: 'Nyquist bin 被丢掉的话这里会恒为 0');
    // Nyquist 频率 = 每点反号
    for (int i = mid; i < mid + 16; i++) {
      expect(out[i] * out[i + 1], lessThan(0), reason: 'Nyquist 频率应逐点反号');
    }
  });

  test('长音频(T≥512 帧)不因帧数算错而错位', () {
    // 513 bins 下帧数必须用 bins 整除;用 512 会在 T≥512 时多算一帧,
    // 导致 flat 索引 k*t+fi 整体错位(约 5.5 秒以上的音频直接变噪声)。
    const int frames = 520;
    final List<double> x = _signal(frames);
    final ({List<double> real, List<double> imag, int frames}) s = _stft(x);
    expect(s.frames, frames);

    final Float32List out = istft(s.real, s.imag, _nFft, _hop, _win, 0);
    expect(out.length, (frames - 1) * _hop + _win);
    expect(
      _maxErr(x, out, skip: _hop),
      lessThan(1e-4),
      reason: '帧数算错会让索引整体错位,重建结果与原文完全无关',
    );
  });
}
