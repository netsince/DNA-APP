import 'dart:math' as math;
import 'dart:typed_data';

/// 确定性 RNG（PCG64，精确复刻 numpy default_rng）见 `tts_random.dart`。

/// 应用 top-k / top-p 过滤，返回过滤后的 logits（与 numpy 实现一致）。
Float64List topPkLogits(
  List<double> logits, {
  required double topP,
  required int topK,
  int minTokensToKeep = 3,
}) {
  final int n = logits.length;
  final Float64List out = Float64List.fromList(logits);

  if (topK > 0) {
    final int k = math.min(topK, n);
    final List<double> sorted = List<double>.of(logits)..sort();
    final double kth = sorted[n - k];
    for (int i = 0; i < n; i++) {
      if (out[i] < kth) out[i] = double.negativeInfinity;
    }
  }

  if (topP < 1.0) {
    // 降序索引
    final List<int> idx = List<int>.generate(n, (int i) => i);
    idx.sort((int a, int b) => out[b].compareTo(out[a]));
    // 安全 logits（-inf 替换为该帧有限最大值）
    double finiteMax = double.negativeInfinity;
    for (int i = 0; i < n; i++) {
      if (out[i].isFinite && out[i] > finiteMax) finiteMax = out[i];
    }
    if (finiteMax == double.negativeInfinity) finiteMax = -1e30;
    final List<double> safe = List<double>.generate(n, (int i) {
      return out[i].isFinite ? out[i] : finiteMax;
    });
    // sorted probs（按 idx 降序）
    double maxLog = double.negativeInfinity;
    for (int i = 0; i < n; i++) {
      final double v = safe[idx[i]];
      if (v > maxLog) maxLog = v;
    }
    final List<double> sortedProbs = List<double>.generate(n, (int i) {
      return math.exp(safe[idx[i]] - maxLog);
    });
    double sum = 0;
    for (int i = 0; i < n; i++) {
      sum += sortedProbs[i];
    }
    for (int i = 0; i < n; i++) {
      sortedProbs[i] /= sum;
    }
    // cumulative
    final List<double> cum = List<double>.filled(n, 0);
    cum[0] = sortedProbs[0];
    for (int i = 1; i < n; i++) {
      cum[i] = cum[i - 1] + sortedProbs[i];
    }
    // remove mask（在排序空间 idx 上）。与 numpy 一致：
    //   remove[i] = (cum[i] - sortedProbs[i]) > topP   （即前 i-1 项概率和 > topP）
    //   remove[:min_keep] = False（至少保留 min_keep 个）
    final List<bool> removed = List<bool>.filled(n, false);
    final int minKeep = math.min(minTokensToKeep, n);
    for (int i = minKeep; i < n; i++) {
      if (cum[i] - sortedProbs[i] > topP) removed[idx[i]] = true;
    }
    for (int i = 0; i < n; i++) {
      if (removed[i]) out[i] = double.negativeInfinity;
    }
  }
  return out;
}

/// 对 logits 做 softmax 归一化（沿 token 轴）。
Float64List softmax(List<double> logits) {
  double m = double.negativeInfinity;
  for (final double v in logits) {
    if (v > m) m = v;
  }
  final Float64List out = Float64List(logits.length);
  double s = 0;
  for (int i = 0; i < logits.length; i++) {
    out[i] = math.exp(logits[i] - m);
    s += out[i];
  }
  if (s <= 0 || !s.isFinite) {
    for (int i = 0; i < logits.length; i++) {
      out[i] = 1.0;
    }
  } else {
    for (int i = 0; i < logits.length; i++) {
      out[i] /= s;
    }
  }
  return out;
}

/// 重复惩罚（与 numpy custom_repetition_penalty 一致）。
List<double> applyRepetitionPenalty(
  List<double> logits,
  List<int> inputIds,
  double penalty,
  int maxInputIds,
  int pastWindow,
) {
  if (penalty == 1.0) return logits;
  final int n = logits.length;
  final List<int> window = inputIds.length <= pastWindow
      ? inputIds
      : inputIds.sublist(inputIds.length - pastWindow);
  final List<int> freq = List<int>.filled(n, 0);
  for (final int id in window) {
    if (id >= 0 && id < n) freq[id]++;
  }
  final List<double> out = List<double>.of(logits);
  for (int i = 0; i < n; i++) {
    if (i >= maxInputIds) continue;
    final double alpha = math.pow(penalty, freq[i]).toDouble();
    out[i] = logits[i] < 0 ? logits[i] * alpha : logits[i] / alpha;
  }
  return out;
}

/// 计算一个复频谱向量的幅度（供校验用）。
double norm(List<double> v) {
  double s = 0;
  for (final double x in v) {
    s += x * x;
  }
  return math.sqrt(s);
}

/// numpy.linalg.norm 默认（Frobenius）对一个向量。
double linalgNorm(Float32List v) {
  double s = 0;
  for (final double x in v) {
    s += x * x;
  }
  return math.sqrt(s);
}

// ===========================================================================
// 逆 STFT（复刻 chattts_onnx.numpy_istft）
// ===========================================================================
/// 输入 real/imag 均为 [n_fft, T]（单 batch）。n_fft 必须是 2 的幂。
/// 返回 [T-1)*hop + win] 长度的波形（单声道）。
Float32List istft(
  List<double> realFlat,
  List<double> imagFlat,
  int nFft,
  int hop,
  int win,
  int pad,
) {
  // Vocos 输出的 real/imag 为 [n_fft/2, T]（bin 优先，numpy irfft 的输入），
  // 与 numpy_istft 的 irfft(spec, n=n_fft) 一致：读 bins 0..half-1，Nyquist(=half) 置 0。
  final int half = nFft ~/ 2;
  final int t = (realFlat.length ~/ half); // 帧数
  // window = hanning(win)
  final Float64List window = Float64List(win);
  for (int i = 0; i < win; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (win - 1));
  }

  // 每帧 irfft(spec, n=n_fft) → 时域帧 [n_fft]
  final List<Float64List> frames = List<Float64List>.generate(t, (int fi) {
    // 构造全谱
    final List<double> re = List<double>.filled(nFft, 0);
    final List<double> im = List<double>.filled(nFft, 0);
    // bin 0..half-1 来自输入
    for (int k = 0; k < half; k++) {
      final int o = k * t + fi;
      re[k] = realFlat[o];
      im[k] = imagFlat[o];
    }
    // bin = half (Nyquist) 置 0；负频率 = 共轭
    re[half] = 0;
    im[half] = 0;
    for (int k = 1; k < half; k++) {
      re[nFft - k] = re[k];
      im[nFft - k] = -im[k];
    }
    // 时域（IFFT 后取实部，此处直接用频率→时域逆变换）
    final Float64List frame = ifftReal(re, im, nFft);
    // 乘窗
    for (int i = 0; i < win && i < nFft; i++) {
      frame[i] *= window[i];
    }
    return frame;
  });

  final int outputSize = (t - 1) * hop + win;
  final Float64List y = Float64List(outputSize);
  final Float64List env = Float64List(outputSize);
  for (int fi = 0; fi < t; fi++) {
    final Float64List frame = frames[fi];
    final int start = fi * hop;
    for (int i = 0; i < win; i++) {
      if (start + i >= outputSize) break;
      y[start + i] += frame[i];
      env[start + i] += window[i] * window[i];
    }
  }

  final int crop = pad;
  final int outLen = outputSize - 2 * crop;
  final Float32List out = Float32List(outLen);
  for (int i = 0; i < outLen; i++) {
    final double e = env[i + crop];
    out[i] = (e > 1e-8) ? (y[i + crop] / e).toDouble() : 0.0;
  }
  return out;
}

/// 对复频谱做逆 FFT（radix-2，长度 n 为 2 的幂），返回实部时域序列。
Float64List ifftReal(List<double> re, List<double> im, int n) {
  // 复 IFFT：X[k] = (1/n) sum x[m] e^{i 2π km/n}；此处 x 为频域，y 为时域
  // 用带 scale 的 FFT（bit-reversal + 蝶形）
  final Float64List yr = Float64List(n);
  final Float64List yi = Float64List(n);
  for (int i = 0; i < n; i++) {
    yr[i] = re[i];
    yi[i] = im[i];
  }
  _fft(yr, yi, n, invert: true);
  return yr;
}

void _fft(Float64List re, Float64List im, int n, {required bool invert}) {
  // bit-reversal permutation
  for (int i = 1, j = 0; i < n; i++) {
    int bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final double tr = re[i]; re[i] = re[j]; re[j] = tr;
      final double ti = im[i]; im[i] = im[j]; im[j] = ti;
    }
  }
  for (int len = 2; len <= n; len <<= 1) {
    final double ang = (invert ? 2 : -2) * math.pi / len;
    final double wr = math.cos(ang);
    final double wi = math.sin(ang);
    for (int i = 0; i < n; i += len) {
      double cr = 1, ci = 0;
      for (int k = 0; k < len ~/ 2; k++) {
        final int a = i + k;
        final int b = i + k + len ~/ 2;
        final double tr = re[b] * cr - im[b] * ci;
        final double ti = re[b] * ci + im[b] * cr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
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
