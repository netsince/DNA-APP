import 'dart:convert';
import 'dart:io';

/// 复刻 ChatTTS 使用的 transformers `BertTokenizerFast`（WordPiece）。
///
/// 流程：BertNormalizer(clean_text + 中文分词 + lowercase) → BertPreTokenizer
/// (按空白/标点切词) → WordPiece（贪心最长匹配 + `##` 续词）→ added tokens 保整。
/// 与 `tokenizer.json` 运行时解析，兼容端侧按需下载。
class WordPieceTokenizer {
  WordPieceTokenizer._(this._tokenToId, this._addedTokens);

  /// 完整词表（含 added tokens）：token -> id。
  final Map<String, int> _tokenToId;

  /// added tokens（特殊 token）：字符串 -> id。
  final Map<String, int> _addedTokens;

  late final Map<int, String> _idToToken =
      _tokenToId.map((String k, int v) => MapEntry(v, k));

  static const String _prefix = '##';
  static const int _maxInputCharsPerWord = 100;

  int get unkId => _tokenToId['[UNK]'] ?? 100;

  /// 从 HuggingFace `tokenizer.json` 文件加载。
  static WordPieceTokenizer fromFile(String tokenizerJsonPath) {
    final Map<String, dynamic> json = jsonDecode(
          File(tokenizerJsonPath).readAsStringSync(),
        )
        as Map<String, dynamic>;
    return fromJson(json);
  }

  static WordPieceTokenizer fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> model = json['model'] as Map<String, dynamic>;
    final Map<String, dynamic> rawVocab = model['vocab'] as Map<String, dynamic>;
    final Map<String, int> tokenToId = <String, int>{
      for (final MapEntry<String, dynamic> e in rawVocab.entries)
        e.key: (e.value as num).toInt(),
    };
    final Map<String, int> addedTokens = <String, int>{};
    final List<dynamic>? added = json['added_tokens'] as List<dynamic>?;
    if (added != null) {
      for (final dynamic a in added) {
        final Map<String, dynamic> m = a as Map<String, dynamic>;
        addedTokens[m['content'] as String] = (m['id'] as num).toInt();
      }
    }
    // added tokens 也并入完整词表（用于 decode）
    tokenToId.addAll(addedTokens);
    return WordPieceTokenizer._(tokenToId, addedTokens);
  }

  // ---- 暴露给引擎的关键 id ----
  int get spkEmbId => _addedTokens['[spk_emb]'] ?? 21143;
  int get break0Id => _addedTokens['[break_0]'] ?? 21147;
  int get eosId => _addedTokens['[Ebreak]'] ?? 21136;

  /// 与 `speaker.decorate_text_prompts` / `decorate_code_prompts` 一致。
  String decorateTextPrompt(String text, [String prompt = '']) =>
      '[Sbreak]$text[Pbreak]$prompt';

  String decorateCodePrompt(
    String text,
    String prompt, {
    required bool hasSpeaker,
  }) {
    final String cleaned = text
        .replaceAll('[Stts]', '')
        .replaceAll('[spk_emb]', '')
        .replaceAll('[empty_spk]', '')
        .trim();
    final String body = (prompt.isNotEmpty ? prompt : '') + cleaned;
    final String smp = ''; // txt_smp 在此路径恒为空
    if (hasSpeaker) {
      return '[Stts][spk_emb]$smp$body[Ptts]';
    }
    return '[Stts][empty_spk]$smp$body[Ptts]';
  }

  // ---- 规范化 ----
  bool _isControl(int cp) =>
      (cp >= 0x00 && cp <= 0x1f) || (cp >= 0x7f && cp <= 0x9f);

  bool _isChineseChar(int cp) =>
      (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x20000 && cp <= 0x2A6DF) ||
      (cp >= 0x2A700 && cp <= 0x2B73F) ||
      (cp >= 0x2B740 && cp <= 0x2B81F) ||
      (cp >= 0x2B820 && cp <= 0x2CEAF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0x2F800 && cp <= 0x2FA1F);

  String _cleanText(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      if (cp == 0) {
        sb.write(' ');
      } else if (_isControl(cp)) {
        // 移除控制字符
      } else {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  String _handleChineseChars(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      if (_isChineseChar(cp)) {
        sb.write(' ');
        sb.writeCharCode(cp);
        sb.write(' ');
      } else {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  String _normalize(String text) {
    String s = _cleanText(text);
    s = _handleChineseChars(s);
    s = s.toLowerCase();
    return s;
  }

  // ---- 预分词：空白 + 标点 ----
  bool _isWordChar(String ch) {
    // 近似 Rust/BERT 的 Unicode \w：字母、数字、_ 。
    // Dart \w 为 ASCII，故用 \p{L}/\p{N} 覆盖中文等。
    return RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
  }

  List<String> _splitPunctuation(String token) {
    final List<String> out = <String>[];
    final StringBuffer cur = StringBuffer();
    bool? curIsWord;
    for (final String ch in token.split('')) {
      final bool isWord = _isWordChar(ch);
      if (curIsWord != null && curIsWord != isWord) {
        out.add(cur.toString());
        cur.clear();
      }
      cur.write(ch);
      curIsWord = isWord;
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  List<String> _preTokenize(String text) {
    final List<String> tokens = <String>[];
    for (final String token in text.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      tokens.addAll(_splitPunctuation(token));
    }
    return tokens;
  }

  // ---- WordPiece ----
  List<String> _wordPiece(String word) {
    if (word.length > _maxInputCharsPerWord) {
      return <String>['[UNK]'];
    }
    final List<String> out = <String>[];
    bool isBad = false;
    int start = 0;
    while (start < word.length) {
      int end = word.length;
      String? cur;
      while (start < end) {
        final String sub = start == 0
            ? word.substring(start, end)
            : _prefix + word.substring(start, end);
        if (_tokenToId.containsKey(sub)) {
          cur = sub;
          break;
        }
        end--;
      }
      if (cur == null) {
        isBad = true;
        break;
      }
      out.add(cur);
      start = end;
    }
    if (isBad) return <String>['[UNK]'];
    return out;
  }

  // ---- 编码 ----
  /// 对文本编码为 id 序列（不添加 [CLS]/[SEP]，与 encode_plus(add_special_tokens=False) 一致）。
  ///
  /// 特殊 token（added tokens）在规范化（lowercase）之前匹配，保持大小写敏感。
  List<int> encode(String text) {
    final List<int> ids = <int>[];
    for (final String seg in _splitAddedTokens(text)) {
      if (_addedTokens.containsKey(seg)) {
        ids.add(_addedTokens[seg]!);
        continue;
      }
      final String norm = _normalize(seg);
      for (final String word in _preTokenize(norm)) {
        for (final String piece in _wordPiece(word)) {
          ids.add(_tokenToId[piece] ?? unkId);
        }
      }
    }
    return ids;
  }

  /// 扫描文本，把 added token（形如 `[xxx]`）作为整体段切出。
  List<String> _splitAddedTokens(String text) {
    // 收集文本中出现的 added token 字符串
    final List<String> present = _addedTokens.keys
        .where(text.contains)
        .toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    if (present.isEmpty) return <String>[text];
    final List<String> out = <String>[];
    final RegExp re = RegExp(present.map(RegExp.escape).join('|'));
    int last = 0;
    for (final RegExpMatch m in re.allMatches(text)) {
      if (m.start > last) out.add(text.substring(last, m.start));
      out.add(m.group(0)!);
      last = m.end;
    }
    if (last < text.length) out.add(text.substring(last));
    return out;
  }

  // ---- 解码 ----
  String decode(List<int> ids, {bool skipSpecialTokens = false}) {
    final List<String> toks = <String>[];
    for (final int id in ids) {
      final String? tok = _idToToken[id];
      if (tok == null) continue;
      if (tok.startsWith(_prefix)) {
        toks.add(tok.substring(2));
      } else {
        if (toks.isEmpty) {
          toks.add(tok);
        } else {
          toks.add(' $tok');
        }
      }
    }
    String out = _cleanUpTokenization(toks.join());
    if (skipSpecialTokens) {
      for (final String t in _addedTokens.keys) {
        out = out.replaceAll(' $t', '').replaceAll(t, '');
      }
    }
    return out;
  }

  /// 去除 token 拼接产生的多余空格（对标 BERT clean_up_tokenization）。
  String _cleanUpTokenization(String s) {
    String out = s
        .replaceAll(' .', '.')
        .replaceAll(' ?', '?')
        .replaceAll(' !', '!')
        .replaceAll(' ,', ',')
        .replaceAll(' ；', '；')
        .replaceAll(' 。', '。')
        .replaceAll(' ，', '，')
        .replaceAll(' ？', '？')
        .replaceAll(' ！', '！')
        .replaceAll(' ！', '！')
        .replaceAll(' ：', '：')
        .replaceAll('： ', '：');
    // 去掉中文（CJK）字符两旁的空白
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < out.length; i++) {
      final String ch = out[i];
      if (ch == ' ' && i > 0 && i < out.length - 1) {
        final int prev = out.codeUnitAt(i - 1);
        final int next = out.codeUnitAt(i + 1);
        if (_isChineseChar(prev) || _isChineseChar(next)) {
          continue;
        }
      }
      sb.write(ch);
    }
    out = sb.toString().replaceAll(RegExp(r'\s+'), ' ');
    return out.trim();
  }
}
