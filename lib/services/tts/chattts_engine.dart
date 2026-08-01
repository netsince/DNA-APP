import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'ort_engine.dart';
import 'tts_math.dart';
import 'wordpiece_tokenizer.dart';

/// 常量（与 Python 端一致）
const int kNumericVq = 4;
const int kHidden = 768;
const int kNumAudio = 626;
const int kNumText = 21178;
const int kNumLayers = 20;
const int kNumHeads = 12;
const int kHeadDim = 64;

class ChatTtsEngine {
  ChatTtsEngine({
    required this.modelsDir,
    required String tokenizerJsonPath,
    required Map<String, dynamic> speakerJson,
    this.threads = 2,
  })  : tokenizer = WordPieceTokenizer.fromFile(tokenizerJsonPath),
        _spkStd = Float32List.fromList(
            (speakerJson['std'] as List).map((dynamic x) => (x as num).toDouble()).toList()),
        _spkMean = Float32List.fromList(
            (speakerJson['mean'] as List).map((dynamic x) => (x as num).toDouble()).toList()),
        _ort = OrtEngine(threads: threads);

  final String modelsDir;
  final WordPieceTokenizer tokenizer;
  final Float32List _spkStd;
  final Float32List _spkMean;
  final OrtEngine _ort;
  final int threads;

  /// 合成一段文本为 24kHz 单声道浮点音频。
  Float32List synthesize(
    String text, {
    int? seed,
    double temperature = 0.3,
    double topP = 0.7,
    int topK = 20,
    double repetitionPenalty = 1.05,
    int maxNewText = 384,
    int maxNewCode = 2048,
    bool doRefine = true,
    void Function(double progress)? onProgress,
  }) {
    // 切分文本（与 Python 一致）
    final List<String> texts = _splitText(text);

    // 采样 speaker 向量
    final Float32List spkVec = _sampleSpeaker(seed);
    final double spkNorm = linalgNorm(spkVec);
    final Float32List spkNormed = Float32List(kHidden);
    for (int i = 0; i < kHidden; i++) {
      spkNormed[i] = spkVec[i] / (spkNorm < 1e-12 ? 1 : spkNorm);
    }

    final List<Float32List> wavs = <Float32List>[];
    for (final String rawPart in texts) {
      String part = rawPart.trim();
      if (part.isEmpty) continue;
      // refine 约占 0~20%，code 生成约占 20~95%，后处理 95~100%
      if (doRefine) {
        part = _refineText(
          part,
          temperature: 0.7,
          maxNewToken: maxNewText,
          seed: seed,
          onProgress: (double p) => onProgress?.call(p * 0.20),
        );
      }
      // code 生成
      final String decorated = tokenizer.decorateCodePrompt(
        part,
        '',
        hasSpeaker: true,
      );
      final List<int> ids = tokenizer.encode(decorated);
      final int startIdx = ids.length;
      final Float32List emb = _embedText(ids);
      final Float32List embSpk = _applySpeaker(emb, ids, spkNormed);
      final int numCode = kNumAudio - 1;
      final Int64List codeIds = _generateCode(
        embSpk,
        ids,
        eosToken: numCode,
        temperature: temperature,
        topP: topP,
        topK: topK,
        maxNewToken: maxNewCode,
        repetitionPenalty: repetitionPenalty,
        seed: seed,
        onProgress: (double p) => onProgress?.call(0.20 + p * 0.75),
      );
      // 取生成部分
      final int totalLen = codeIds.length ~/ 4;
      final int genLen = totalLen - startIdx;
      if (genLen <= 0) continue;
      // codes [4, T]
      final Int64List codes = Int64List(4 * genLen);
      for (int v = 0; v < 4; v++) {
        for (int t = 0; t < genLen; t++) {
          codes[v * genLen + t] = codeIds[(startIdx + t) * 4 + v];
        }
      }
      // DVAE: codes [1,4,T] -> mel [1,100,T]
      final OrtSessionWrapper dvae = _ort.dvae(modelsDir);
      final List<OrtValue> dvaeOut = dvae.run(
            <String, Float32List>{},
            <String, Int64List>{'codes': codes},
            <String, List<int>>{'codes': <int>[1, 4, genLen]},
            outputNames: <String>['mel'],
          );
      final Float32List melFlat = dvae.readFloatTensor(dvaeOut[0]);
      final int tMel = melFlat.length ~/ 100;
      dvaeOut[0].release();
      // Vocos: mel [1,100,T] -> real/imag
      final OrtSessionWrapper vocos = _ort.vocos(modelsDir);
      final List<OrtValue> vocOut = vocos.run(
            <String, Float32List>{'mel': melFlat},
            <String, Int64List>{},
            <String, List<int>>{'mel': <int>[1, 100, tMel]},
            outputNames: <String>['real', 'imag'],
          );
      final Float32List realFlat = vocos.readFloatTensor(vocOut[0]);
      final Float32List imagFlat = vocos.readFloatTensor(vocOut[1]);
      vocOut[0].release();
      vocOut[1].release();
      // istft
      final Float32List wav = istft(
        realFlat.toList(),
        imagFlat.toList(),
        1024,
        256,
        1024,
        384,
      );
      wavs.add(wav);
      onProgress?.call(1.0);
    }

    if (wavs.isEmpty) return Float32List(0);
    final int total = wavs.fold<int>(0, (int s, Float32List w) => s + w.length);
    final Float32List out = Float32List(total);
    int off = 0;
    for (final Float32List w in wavs) {
      out.setRange(off, off + w.length, w);
      off += w.length;
    }
    return out;
  }

  // ---- 文本切分 ----
  List<String> _splitText(String text) {
    if (text.contains('\n')) {
      return text
          .split('\n')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    final List<String> parts = <String>[];
    final RegExp re = RegExp(r'(?<=。)|(?<=\.\s)');
    for (final String s in text.split(re)) {
      if (s.isNotEmpty) parts.add(s);
    }
    if (parts.isEmpty) parts.add(text);
    return parts;
  }

  // ---- speaker 采样 ----
  Float32List _sampleSpeaker(int? seed) {
    final Float32List out = Float32List(kHidden);
    if (seed != null) {
      final TtsRandom rng = TtsRandom(seed);
      for (int i = 0; i < kHidden; i++) {
        out[i] = (rng.nextGaussian() * _spkStd[i] + _spkMean[i]).toDouble();
      }
    } else {
      final TtsRandom rng = TtsRandom(DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
      for (int i = 0; i < kHidden; i++) {
        out[i] = (rng.nextGaussian() * _spkStd[i] + _spkMean[i]).toDouble();
      }
    }
    return out;
  }

  // ---- 文本嵌入 ----
  /// ids: [T] 文本 token（长度可能含 spk_emb）。返回 emb [T, H]。
  Float32List _embedText(List<int> ids) {
    final int t = ids.length;
    final Float32List emb = Float32List(t * kHidden);
    final List<int> textIds = List<int>.of(ids);
    // 文本位置全部有效（无 prompt 场景）
    final OrtSessionWrapper embSess = _ort.embText(modelsDir);
    final List<OrtValue> out = embSess.run(
          <String, Float32List>{},
          <String, Int64List>{'text_ids': Int64List.fromList(textIds)},
          <String, List<int>>{'text_ids': <int>[1, t]},
          outputNames: <String>['emb'],
        );
    final Float32List embFlat = embSess.readFloatTensor(out[0]);
    out[0].release();
    for (int i = 0; i < embFlat.length; i++) {
      emb[i] = embFlat[i];
    }
    return emb;
  }

  /// 在 [spk_emb] 位置替换为归一化 speaker 向量。
  Float32List _applySpeaker(Float32List emb, List<int> ids, Float32List spkNormed) {
    final int t = ids.length;
    final Float32List out = Float32List.fromList(emb);
    for (int i = 0; i < t; i++) {
      if (ids[i] == tokenizer.spkEmbId) {
        out.setRange(i * kHidden, (i + 1) * kHidden, spkNormed);
      }
    }
    return out;
  }

  // ---- 精炼（refine，文本 GPT） ----
  String _refineText(
    String text, {
    required double temperature,
    required int maxNewToken,
    int? seed,
    void Function(double progress)? onProgress,
  }) {
    final String decorated = tokenizer.decorateTextPrompt(text);
    final List<int> ids = tokenizer.encode(decorated);
    final int startIdx = ids.length;
    final Float32List emb = _embedText(ids);
    final Int64List gen = _generateText(
      emb,
      ids,
      eosToken: tokenizer.eosId,
      temperature: temperature,
      topP: 0.7,
      topK: 20,
      maxNewToken: maxNewToken,
      repetitionPenalty: 1.0,
      seed: seed,
      onProgress: onProgress,
    );
    // 取生成部分，跳过所有特殊 token（>= break_0_ids 的过滤掉，保留文本）。
    // 与 Python `new_ids[new_ids < break_0_ids]` 一致：是过滤而非遇到第一个就 break。
    final List<int> newIds = <int>[];
    for (int i = startIdx; i < gen.length ~/ 4; i++) {
      final int id = gen[i * 4];
      if (id >= tokenizer.break0Id) continue;
      newIds.add(id);
    }
    return tokenizer.decode(newIds);
  }

  // ---- GPT 前向（含 KV cache） ----
  /// past 的每个条目携带 (数据, 真实shape)，回喂时原样使用，
  /// 以适配本模型 KV cache 的首维可能非 1（导出怪癖，Python 端为 40）。
  (Float32List hidden, Map<String, (Float32List, List<int>)> past) _gptForward(
    Float32List inputsEmbeds, // [T, H]
    Float32List attentionMask, // [T]
    Int64List positionIds, // [T]
    Map<String, (Float32List, List<int>)>? past,
  ) {
    final int t = inputsEmbeds.length ~/ kHidden;
    final Map<String, Float32List> floatInputs = <String, Float32List>{
      'inputs_embeds': inputsEmbeds,
      'attention_mask': attentionMask,
    };
    final Map<String, Int64List> intInputs = <String, Int64List>{
      'position_ids': positionIds,
    };
    final Map<String, List<int>> shapes = <String, List<int>>{
      'inputs_embeds': <int>[1, t, kHidden],
      // attention_mask 覆盖「past 缓存 + 当前 token」的完整长度，
      // 循环里 inputs_embeds 只有 1 个 token，但 mask 长度 = 1 + past_len。
      'attention_mask': <int>[1, attentionMask.length],
      'position_ids': <int>[1, t],
    };
    if (past == null) {
      for (int i = 0; i < kNumLayers; i++) {
        final String nameK = 'past.${2 * i}.k';
        final String nameV = 'past.${2 * i + 1}.v';
        floatInputs[nameK] = Float32List(0);
        floatInputs[nameV] = Float32List(0);
        shapes[nameK] = <int>[1, kNumHeads, 0, kHeadDim];
        shapes[nameV] = <int>[1, kNumHeads, 0, kHeadDim];
      }
    } else {
      for (int i = 0; i < kNumLayers; i++) {
        final String nameK = 'past.${2 * i}.k';
        final String nameV = 'past.${2 * i + 1}.v';
        floatInputs[nameK] = past[nameK]!.$1;
        floatInputs[nameV] = past[nameV]!.$1;
        shapes[nameK] = past[nameK]!.$2;
        shapes[nameV] = past[nameV]!.$2;
      }
    }

    final OrtSessionWrapper gpt = _ort.gpt(modelsDir);
    final List<OrtValue> out = gpt.run(
          floatInputs,
          intInputs,
          shapes,
          outputNames: _gptOutputNames(),
        );
    final Float32List hidden = gpt.readFloatTensor(out[0]);
    final Map<String, (Float32List, List<int>)> newPast =
        <String, (Float32List, List<int>)>{};
    for (int i = 0; i < kNumLayers * 2; i++) {
      // present.{i}.{k/v} 对应回灌的 past.{i}.{k/v}（i 偶为 k，奇为 v）
      newPast['past.$i.${i.isEven ? 'k' : 'v'}'] = (
        gpt.readFloatTensor(out[1 + i]),
        gpt.readFloatTensorShape(out[1 + i]),
      );
    }
    for (final OrtValue v in out) {
      v.release();
    }
    return (hidden, newPast);
  }

  List<String> _gptOutputNames() {
    // 模型输出为 present.0.k, present.1.v, ...（按层 k/v 交替）
    final List<String> names = <String>['hidden'];
    for (int i = 0; i < kNumLayers * 2; i++) {
      names.add('present.$i.${i.isEven ? 'k' : 'v'}');
    }
    return names;
  }

  // ---- 自回归生成（文本与 code 共用骨架） ----
  /// [inferText] 为 true：head_text 生成单 token 并复制到 4 vq；否则 head_code 生成 4 路 vq。
  Int64List _generate(
    Float32List emb, // [T,H]
    List<int> inputIds, // [T]
    {
    required int eosToken,
    required bool inferText,
    required double temperature,
    required double topP,
    required int topK,
    required int maxNewToken,
    required double repetitionPenalty,
    int? seed,
    void Function(double progress)? onProgress,
  }) {
    final int t = emb.length ~/ kHidden;
    // 注意：inputIds 需展开为 4 vq
    Int64List seq4 = Int64List(t * 4);
    for (int i = 0; i < t; i++) {
      for (int v = 0; v < 4; v++) {
        seq4[i * 4 + v] = inputIds[i];
      }
    }
    final Float32List attn = Float32List(t);
    for (int i = 0; i < t; i++) attn[i] = 1;
    final Int64List pos = Int64List(t);
    for (int i = 0; i < t; i++) pos[i] = i;

    final (Float32List hidden, Map<String, (Float32List, List<int>)> past) =
        _gptForward(emb, attn, pos, null);
    Float32List curHidden = Float32List.fromList(
      hidden.sublist((t - 1) * kHidden, t * kHidden),
    );

    final TtsRandom rng = seed != null ? TtsRandom(seed) : TtsRandom(_randSeed());

    for (int step = 0; step < maxNewToken; step++) {
      int next0 = -1;
      Int64List newTokens;
      if (inferText) {
        final OrtSessionWrapper headSess = _ort.headText(modelsDir);
        final List<OrtValue> head = headSess.run(
              <String, Float32List>{'hidden': curHidden},
              <String, Int64List>{},
              <String, List<int>>{'hidden': <int>[1, 1, kHidden]},
              outputNames: <String>['logits'],
            );
        final Float32List logits = headSess.readFloatTensor(head[0]);
        head[0].release();
        List<double> l = logits.toList();
        for (int i = 0; i < l.length; i++) l[i] /= temperature;
        if (repetitionPenalty != 1.0) {
          l = applyRepetitionPenalty(l, seq4.toList(), repetitionPenalty, kNumText, 16);
        }
        final Float64List filtered = topPkLogits(l, topP: topP, topK: topK);
        final Float64List probs = softmax(filtered.toList());
        next0 = rng.choice(probs.toList());
        newTokens = Int64List(4)..fillRange(0, 4, next0);
        if (next0 == eosToken) break;
      } else {
        // head_code: hidden [1,1,H] -> [1,1,626,4]
        final OrtSessionWrapper headSess = _ort.headCode(modelsDir);
        final List<OrtValue> head = headSess.run(
              <String, Float32List>{'hidden': curHidden},
              <String, Int64List>{},
              <String, List<int>>{'hidden': <int>[1, 1, kHidden]},
              outputNames: <String>['logits'],
            );
        final Float32List logits4 = headSess.readFloatTensor(head[0]); // [626*4]
        head[0].release();
        newTokens = Int64List(4);
        for (int v = 0; v < 4; v++) {
          // 每路 vq 独立归一化。
          // head_code 输出 [B,T,626,4]，末位是 vq、626 是词表，行主序扁平索引 = k*4 + v。
          final List<double> l = List<double>.generate(kNumAudio, (int k) {
            return logits4[k * 4 + v] / temperature;
          });
          final Float64List filtered = topPkLogits(l, topP: topP, topK: topK);
          final Float64List probs = softmax(filtered.toList());
          newTokens[v] = rng.choice(probs.toList());
        }
        if (newTokens.any((int x) => x == eosToken)) break;
      }

      // 追加
      final int oldLen = seq4.length ~/ 4;
      final Int64List newSeq = Int64List((oldLen + 1) * 4);
      newSeq.setRange(0, seq4.length, seq4);
      newSeq.setRange(oldLen * 4, oldLen * 4 + 4, newTokens);
      seq4 = newSeq;

      // 下一步嵌入
      final Float32List nextEmb;
      if (inferText) {
        final OrtSessionWrapper embSess = _ort.embText(modelsDir);
        final List<OrtValue> eOut = embSess.run(
              <String, Float32List>{},
              <String, Int64List>{'text_ids': Int64List.fromList(<int>[next0])},
              <String, List<int>>{'text_ids': <int>[1, 1]},
              outputNames: <String>['emb'],
            );
        nextEmb = embSess.readFloatTensor(eOut[0]);
        eOut[0].release();
      } else {
        final OrtSessionWrapper embSess = _ort.embCode(modelsDir);
        final List<OrtValue> eOut = embSess.run(
              <String, Float32List>{},
              <String, Int64List>{'code_ids': newTokens},
              <String, List<int>>{'code_ids': <int>[1, 1, 4]},
              outputNames: <String>['emb'],
            );
        nextEmb = embSess.readFloatTensor(eOut[0]);
        eOut[0].release();
      }

      final int newLen = oldLen + 1;
      final Float32List attnNew = Float32List(newLen);
      for (int i = 0; i < newLen; i++) attnNew[i] = 1;
      final Int64List posNew = Int64List.fromList(<int>[newLen - 1]);
      final (Float32List h2, Map<String, (Float32List, List<int>)> p2) =
          _gptForward(nextEmb, attnNew, posNew, past);
      past..clear()..addAll(p2);
      curHidden = Float32List.fromList(h2.sublist(0, kHidden));
      onProgress?.call((step + 1) / maxNewToken);
    }
    return seq4;
  }

  Int64List _generateText(
    Float32List emb,
    List<int> inputIds, {
    required int eosToken,
    required double temperature,
    required double topP,
    required int topK,
    required int maxNewToken,
    required double repetitionPenalty,
    int? seed,
    void Function(double progress)? onProgress,
  }) {
    return _generate(
      emb,
      inputIds,
      eosToken: eosToken,
      inferText: true,
      temperature: temperature,
      topP: topP,
      topK: topK,
      maxNewToken: maxNewToken,
      repetitionPenalty: repetitionPenalty,
      seed: seed,
      onProgress: onProgress,
    );
  }

  Int64List _generateCode(
    Float32List emb,
    List<int> inputIds, {
    required int eosToken,
    required double temperature,
    required double topP,
    required int topK,
    required int maxNewToken,
    required double repetitionPenalty,
    int? seed,
    void Function(double progress)? onProgress,
  }) {
    return _generate(
      emb,
      inputIds,
      eosToken: eosToken,
      inferText: false,
      temperature: temperature,
      topP: topP,
      topK: topK,
      maxNewToken: maxNewToken,
      repetitionPenalty: repetitionPenalty,
      seed: seed,
      onProgress: onProgress,
    );
  }

  int _randSeed() => DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  /// 释放所有 ONNX 会话（释放内存）。下次 synthesize 会自动重新加载。
  void dispose() => _ort.dispose();
}
