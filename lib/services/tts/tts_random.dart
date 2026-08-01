import 'dart:math' as math;

import 'tts_ziggurat.dart';

/// 确定性 RNG：精确复刻 numpy `default_rng(seed)`（PCG64 + SeedSequence），
/// 使同 seed 的采样序列与 Python 端完全一致。
///
/// - seed 派生：复刻 numpy `SeedSequence.generate_state(4, uint64)`
/// - `nextDouble`：numpy `uint64_to_double` = `(next >> 11) / 2^53`
/// - `nextGaussian`：numpy ziggurat `random_standard_normal`
/// - `choice`：numpy `cdf.searchsorted(side='right')`
class TtsRandom {
  TtsRandom(int seed) {
    _seedFromSequence(seed);
  }

  // PCG64 128-bit state 与 inc（各 high/low 两段 64 位，mask 为无符号）
  late int _stateHigh, _stateLow;
  late int _incHigh, _incLow;

  static const int _m = 0xFFFFFFFFFFFFFFFF;
  static final BigInt _m128 = (BigInt.one << 128) - BigInt.one;

  // ---- numpy SeedSequence 常量 ----
  static const int _initA = 0x43b0d7e5;
  static const int _multA = 0x931e8875;
  static const int _initB = 0x8b51f9dd;
  static const int _multB = 0x58f38ded;
  static const int _mixMultL = 0xca01f9dd;
  static const int _mixMultR = 0x4973f715;
  static const int _xshift = 16;

  // PCG64 乘数常量（128 位）
  static const int _pcgMultHigh = 2549297995355413924;
  static const int _pcgMultLow = 4865540595714422341;

  static int _hashmix(int value, List<int> hashConst) {
    value ^= hashConst[0];
    hashConst[0] = (hashConst[0] * _multA) & 0xFFFFFFFF;
    value = (value * hashConst[0]) & 0xFFFFFFFF;
    value ^= value >> _xshift;
    return value & 0xFFFFFFFF;
  }

  static int _mix(int x, int y) {
    int result = (_mixMultL * x - _mixMultR * y) & 0xFFFFFFFF;
    result ^= result >> _xshift;
    return result & 0xFFFFFFFF;
  }

  /// 整数 seed → uint32 小端词数组（numpy `_int_to_uint32_array`）。
  static List<int> _intToUint32Array(int n) {
    final List<int> arr = <int>[];
    if (n == 0) {
      arr.add(0);
      return arr;
    }
    while (n > 0) {
      arr.add(n & 0xFFFFFFFF);
      n = (n >>> 32) & 0xFFFFFFFF;
    }
    return arr;
  }

  /// numpy `SeedSequence(seed).generate_state(4, uint64)` → 4 个 uint64。
  void _seedFromSequence(int seed) {
    final List<int> entropy = _intToUint32Array(seed);
    const int poolSize = 4;
    final List<int> pool = List<int>.filled(poolSize, 0);

    // mix_entropy(pool, entropy)
    final List<int> hashConst = <int>[_initA];
    for (int i = 0; i < poolSize; i++) {
      pool[i] = _hashmix(i < entropy.length ? entropy[i] : 0, hashConst);
    }
    for (int iSrc = 0; iSrc < poolSize; iSrc++) {
      for (int iDst = 0; iDst < poolSize; iDst++) {
        if (iSrc != iDst) {
          pool[iDst] = _mix(pool[iDst], _hashmix(pool[iSrc], hashConst));
        }
      }
    }
    for (int iSrc = poolSize; iSrc < entropy.length; iSrc++) {
      for (int iDst = 0; iDst < poolSize; iDst++) {
        pool[iDst] = _mix(pool[iDst], _hashmix(entropy[iSrc], hashConst));
      }
    }

    // generate_state(4, uint64)：内部 n_words*2 = 8 个 uint32
    final List<int> state32 = List<int>.filled(8, 0);
    int hashConstB = _initB;
    for (int i = 0; i < 8; i++) {
      int dataVal = pool[i % poolSize];
      dataVal ^= hashConstB;
      hashConstB = (hashConstB * _multB) & 0xFFFFFFFF;
      dataVal = (dataVal * hashConstB) & 0xFFFFFFFF;
      dataVal ^= dataVal >> _xshift;
      state32[i] = dataVal & 0xFFFFFFFF;
    }
    // 8 个 uint32 小端拼成 4 个 uint64（u64[0]=state32[0]|state32[1]<<32 ...）
    final List<int> u64 = List<int>.filled(4, 0);
    for (int i = 0; i < 4; i++) {
      final int lo = state32[i * 2];
      final int hi = state32[i * 2 + 1];
      u64[i] = (lo | (hi << 32)) & _m;
    }

    // PCG64: initstate = (u64[0],u64[1]), initseq = (u64[2],u64[3])
    _pcgSrandom(u64[0], u64[1], u64[2], u64[3]);
  }

  // ---- PCG64 step: state = state*MULT + inc（128 位，取低 128 位）----
  void _step() {
    // 128x128 乘法 mod 2^128，state(high/low) * MULT(high/low)
    final int sl = _stateLow, sh = _stateHigh;
    final int ml = _pcgMultLow, mh = _pcgMultHigh;
    // term: sl*ml, sl*mh, sh*ml（sh*mh 位移到 >=128 位丢弃）
    final (int, int) t0 = _umul128(sl, ml); // (hi, lo)
    final (int, int) t1 = _umul128(sl, mh);
    final (int, int) t2 = _umul128(sh, ml);
    // 低 128 位
    // resLow = t0.lo
    // resHigh = t0.hi + t1.lo + t2.lo  (mod 2^64)
    final int resLow = t0.$2;
    final int resHigh = (t0.$1 + t1.$2 + t2.$2) & _m;

    // state = res + inc（128 位无符号加法，用 BigInt 避免有符号溢出）
    final BigInt mask64 = (BigInt.one << 64) - BigInt.one;
    final BigInt res =
        ((BigInt.from(resHigh) & mask64) << 64) | (BigInt.from(resLow) & mask64);
    final BigInt inc =
        ((BigInt.from(_incHigh) & mask64) << 64) | (BigInt.from(_incLow) & mask64);
    final BigInt sum = (res + inc) & _m128;
    _stateHigh = ((sum >> 64) & mask64).toSigned(64).toInt();
    _stateLow = (sum & mask64).toSigned(64).toInt();
  }

  /// 64x64 无符号乘法 → (hi, lo) 128 位。
  ///
  /// 用 BigInt 精确计算。注意 `BigInt.toInt()` 对 >2^63 的值会饱和成 int 最大值，
  /// 必须先用 `toSigned(64)` 转成正确的有符号 64 位位模式。
  static (int, int) _umul128(int x, int y) {
    final BigInt mask64 = (BigInt.one << 64) - BigInt.one;
    // 只取低 64 位无符号（x/y 可能是有符号负 int，& mask64 得到正确位模式）
    final BigInt a = BigInt.from(x) & mask64;
    final BigInt b = BigInt.from(y) & mask64;
    final BigInt p = a * b;
    final BigInt lo64 = p & mask64;
    final BigInt hi64 = (p >> 64) & mask64;
    final int lo = lo64.toSigned(64).toInt();
    final int hi = hi64.toSigned(64).toInt();
    return (hi, lo);
  }

  /// numpy `pcg_setseq_128_srandom_r`：state=0, inc=(initseq<<1)|1,
  /// step, state+=initstate, step。
  void _pcgSrandom(int ish, int isl, int iqh, int iql) {
    _stateHigh = 0;
    _stateLow = 0;
    // inc = (initseq << 1) | 1
    _incHigh = (((iqh << 1) & _m) | ((iql >>> 63) & 1)) & _m;
    _incLow = ((iql << 1) | 1) & _m;
    _step();
    // state += initstate（128 位无符号加法）
    final BigInt mask64 = (BigInt.one << 64) - BigInt.one;
    final BigInt st =
        ((BigInt.from(_stateHigh) & mask64) << 64) | (BigInt.from(_stateLow) & mask64);
    final BigInt init =
        ((BigInt.from(ish) & mask64) << 64) | (BigInt.from(isl) & mask64);
    final BigInt sum = (st + init) & _m128;
    _stateHigh = ((sum >> 64) & mask64).toSigned(64).toInt();
    _stateLow = (sum & mask64).toSigned(64).toInt();
    _step();
  }

  /// numpy `pcg_setseq_128_xsl_rr_64_random_r`：step 后输出。
  int nextUint64() {
    _step();
    // output_xsl_rr_128_64: rotr64(state.high ^ state.low, state.high >> 58)
    final int x = (_stateHigh ^ _stateLow) & _m;
    final int rot = (_stateHigh >>> 58) & 63;
    final int r = (x >>> rot) | (x << ((-rot) & 63));
    return r & _m;
  }

  /// numpy `uint64_to_double` = `(next >> 11) * (1/2^53)`。
  double nextDouble() => (nextUint64() >>> 11) / 9007199254740992.0;

  /// 标准正态（numpy ziggurat `random_standard_normal`）。
  double nextGaussian() {
    for (;;) {
      final int r = nextUint64();
      final int idx = r & 0xff;
      final int rShifted = r >>> 8;
      final int sign = rShifted & 0x1;
      // rabs 是 52 位无符号整数（fast path 与 ki 直接整数比较）
      final int rabs = (rShifted >> 1) & 0x000fffffffffffff;
      double x = rabs * kZigW[idx];
      if (sign == 1) x = -x;
      if (rabs < kZigKi[idx]) return x;
      if (idx == 0) {
        for (;;) {
          final double xx =
              -kZigNorInvR * _log1p(-nextDouble());
          final double yy = -_log1p(-nextDouble());
          if (yy + yy > xx * xx) {
            return ((rabs >> 8) & 0x1) == 1
                ? -(kZigNorR + xx)
                : kZigNorR + xx;
          }
        }
      } else {
        final double u =
            (kZigF[idx - 1] - kZigF[idx]) * nextDouble() + kZigF[idx];
        if (u < math.exp(-0.5 * x * x)) return x;
      }
    }
  }

  /// numpy `Generator.choice`（replace=True, p 指定）：
  /// `cdf = p.cumsum(); cdf /= cdf[-1]; idx = cdf.searchsorted(r, side='right')`。
  ///
  /// 必须先累加再做整体归一化（`cdf /= cdf[-1]`），且用 `searchsorted(side='right')`
  /// 语义（返回第一个 `cdf[i] > r` 的索引）。与直接 `if (r < cum) return i` 在
  /// 浮点边界处可能不同，导致长序列自回归发散。
  int choice(List<double> probs) {
    final double r = nextDouble();
    // ignore: avoid_print
    if (probs.length == 626) print('DBG_CODE_R $r');
    final int n = probs.length;
    // cdf 累加
    final List<double> cdf = List<double>.filled(n, 0);
    double c = 0;
    for (int i = 0; i < n; i++) {
      c += probs[i];
      cdf[i] = c;
    }
    // cdf /= cdf[-1]（numpy 无条件整体归一化）
    final double total = cdf[n - 1];
    if (total > 0) {
      for (int i = 0; i < n; i++) cdf[i] /= total;
    }
    // searchsorted side='right': 第一个 cdf[i] > r
    for (int i = 0; i < n; i++) {
      if (r < cdf[i]) return i;
    }
    return n - 1;
  }

  // ---- 数学辅助 ----
  /// log(1+x)：当 |x| 很小时用 `x` 近似避免精度丢失；处理 x→-1 的 log(0) 问题。
  static double _log1p(double x) {
    final double one = 1 + x;
    if (one == 1.0) return x;
    return math.log(one) * x / (one - 1);
  }
}
