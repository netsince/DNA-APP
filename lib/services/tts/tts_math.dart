import 'dart:math' as math;
import 'dart:typed_data';

/// 确定性 RNG：xoshiro256**（与 numpy 非逐位一致，但同 seed 在 Dart 内确定）。
/// 用于 GPT 采样与 speaker 采样，保证「同 seed → 同输出」。
class TtsRandom {
  TtsRandom(int seed) {
    // 由 32 位 seed 扩展为 4 个 64 位状态
    _s0 = _splitMix64(seed);
    _s1 = _splitMix64(_s0);
    _s2 = _splitMix64(_s1);
    _s3 = _splitMix64(_s2);
  }

  late int _s0, _s1, _s2, _s3;

  static int _splitMix64(int x) {
    x = (x + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    x = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF;
    x = ((x ^ (x >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF;
    return (x ^ (x >> 31)) & 0xFFFFFFFFFFFFFFFF;
  }

  static int _rotl(int x, int k) =>
      ((x << k) | (x >> (64 - k))) & 0xFFFFFFFFFFFFFFFF;

  /// 返回 [0, 2^64) 的伪随机 64 位整数。
  int nextUint64() {
    final int result = (_rotl(_s1 * 5, 7) * 9) & 0xFFFFFFFFFFFFFFFF;
    final int t = (_s1 << 17) & 0xFFFFFFFFFFFFFFFF;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 45);
    return result;
  }

  /// 返回 [0,1) 的双精度随机数。
  double nextDouble() => (nextUint64() >> 11) / 9007199254740992.0;

  /// 标准正态（Box-Muller）。
  double nextGaussian() {
    double u = 0, v = 0;
    double s = 0;
    do {
      u = nextDouble() * 2 - 1;
      v = nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1 || s == 0);
    return u * math.sqrt(-2.0 * math.log(s) / s);
  }

  /// 按概率分布 `probs`（长度 n，和为 1）采样一个下标。
  int choice(List<double> probs) {
    final double r = nextDouble();
    double cum = 0;
    for (int i = 0; i < probs.length; i++) {
      cum += probs[i];
      if (r < cum) return i;
    }
    return probs.length - 1;
  }
}

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
    for (int i = 0; i < n; i++) sum += sortedProbs[i];
    for (int i = 0; i < n; i++) sortedProbs[i] /= sum;
    // cumulative
    final List<double> cum = List<double>.filled(n, 0);
    cum[0] = sortedProbs[0];
    for (int i = 1; i < n; i++) cum[i] = cum[i - 1] + sortedProbs[i];
    // remove mask（在 idx 排序空间）
    final List<bool> removed = List<bool>.filled(n, false);
    final int minKeep = math.min(minTokensToKeep, n);
    for (int i = n - 1; i >= minKeep; i--) {
      // 从后往前累积，去掉累积概率超过 topP 的
      if (i == n - 1) {
        removed[idx[i]] = (cum[i] - sortedProbs[i]) > topP;
      } else {
        removed[idx[i]] = removed[idx[i + 1]] || (cum[i] - sortedProbs[i]) > topP;
      }
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
    for (int i = 0; i < logits.length; i++) out[i] = 1.0;
  } else {
    for (int i = 0; i < logits.length; i++) out[i] /= s;
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
  for (final double x in v) s += x * x;
  return math.sqrt(s);
}

/// numpy.linalg.norm 默认（Frobenius）对一个向量。
double linalgNorm(Float32List v) {
  double s = 0;
  for (final double x in v) s += x * x;
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
  // 输入为 onnxruntime 展平的 [n_fft, T]（bin 优先）：索引 = bin*T + frame
  final int t = (realFlat.length ~/ nFft); // 帧数
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
    final int half = nFft ~/ 2;
    // bin 0..half（numpy irfft 只取前 n//2+1 个 bin）
    for (int k = 0; k <= half; k++) {
      final int o = k * t + fi;
      re[k] = realFlat[o];
      im[k] = imagFlat[o];
    }
    // 负频率 = 共轭
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
