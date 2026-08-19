/// 语音合成前的文本清理与标点归一化。
///
/// 规则与职责：
/// 1. **括号内容剔除**：移除所有中英文括号 `()` `（）` `【】` `[]` 及其内部内容（支持嵌套）。
/// 2. **台词提取与容错**（仅当 [quoteOnly] 为 true）：
///    - 优先提取成对引号（`"` `“”` `'` `‘’`）内的台词内容；
///    - 若大模型输出残缺（如漏打前引号、单边闭引号等导致提取内容过少或为空），
///      具备智能容错回退机制，避免吞字或漏读。
/// 3. **特殊符号清洗**：剔除 Markdown 标记、Emoji、未登录符号等易引发模型异常的字符。
/// 4. **标点分级归一化与停顿映射**：
///    - 省略号（`...` `……` 连续点等）统一映射为 ChatTTS 停顿标记 `[break_4]`，彻底根除 GPT 发音幻觉（如“坏坏”等杂音）；
///    - 破折号（`——` `～` 等）映射为短停顿标记 `[break_2]`，避免 Tokenizer 错位与自回归死循环；
///    - 标点折叠（`！！！` -> `！`，`？？？` -> `？`），保留情感语调的同时防止重复；
///    - 逗号、顿号、分号归一化为标准短停顿。
String cleanTtsText(String raw, {required bool quoteOnly}) {
  if (raw.trim().isEmpty) return '';

  // 1. 移除中英文括号及内部动作描写
  final String noBracket = _removeBrackets(raw);
  if (noBracket.trim().isEmpty) return '';

  // 2. 台词提取（带单边/破损引号容错）
  final String textToProcess;
  if (quoteOnly) {
    textToProcess = _extractDialogue(noBracket);
  } else {
    textToProcess = noBracket;
  }

  // 3. 标点符号与特殊字符二次深度清洗与停顿映射
  final String normalized = _normalizePunctuationAndTokens(textToProcess);
  return normalized;
}

/// 移除中英文括号（`()` `（）` `【】` `[]`）及其内部内容，支持嵌套。
String _removeBrackets(String s) {
  const List<(String, String)> pairs = <(String, String)>[
    ('(', ')'),
    ('（', '）'),
    ('【', '】'),
    ('[', ']'),
  ];
  final List<int> stack = <int>[];
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final String ch = s[i];
    // 开括号
    bool isOpen = false;
    for (int p = 0; p < pairs.length; p++) {
      if (ch == pairs[p].$1) {
        stack.add(p);
        isOpen = true;
        break;
      }
    }
    if (isOpen) continue;
    // 闭括号（需匹配栈顶的开括号类型）
    if (stack.isNotEmpty && ch == pairs[stack.last].$2) {
      stack.removeLast();
      continue;
    }
    // 不在任何括号内时才输出
    if (stack.isEmpty) out.write(ch);
  }
  return out.toString();
}

/// 提取成对引号（中英文 `"` `“”` `'` `‘’`）内的内容，若大模型引号损坏则智能容错。
String _extractDialogue(String s) {
  const List<(String, String)> pairs = <(String, String)>[
    ('"', '"'),
    ('“', '”'),
    ("'", "'"),
    ('‘', '’'),
  ];
  final List<int> stack = <int>[];
  final StringBuffer content = StringBuffer();
  final List<String> chunks = <String>[];
  bool inQuote = false;

  for (int i = 0; i < s.length; i++) {
    final String ch = s[i];
    // 闭引号优先
    if (stack.isNotEmpty && ch == pairs[stack.last].$2) {
      stack.removeLast();
      if (stack.isEmpty) {
        final String seg = content.toString().trim();
        if (seg.isNotEmpty) chunks.add(seg);
        content.clear();
        inQuote = false;
      }
      continue;
    }
    // 开引号
    bool isOpen = false;
    for (int p = 0; p < pairs.length; p++) {
      if (ch == pairs[p].$1) {
        stack.add(p);
        isOpen = true;
        inQuote = true;
        break;
      }
    }
    if (isOpen) continue;
    // 引号内普通字符
    if (inQuote) content.write(ch);
  }

  // 检查提取效果
  final String quoted = chunks.join('，');
  final int rawHanCount = _countHanOrAlpha(s);
  final int quotedHanCount = _countHanOrAlpha(quoted);

  // 容错回退机制：
  // 若提取结果为空，或提取汉字数远少于去括号后的文字（例如大模型漏打前引号导致大段正文丢失），
  // 则回退到去括号后的全文，并剥离孤立的单边引号。
  if (quotedHanCount == 0 || (rawHanCount >= 6 && quotedHanCount < rawHanCount * 0.4)) {
    return _stripIsolatedQuotes(s);
  }

  return quoted;
}

int _countHanOrAlpha(String text) {
  int count = 0;
  for (final int r in text.runes) {
    if ((r >= 0x4E00 && r <= 0x9FA5) ||
        (r >= 0x3400 && r <= 0x4DBF) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0x41 && r <= 0x5A) ||
        (r >= 0x30 && r <= 0x39)) {
      count++;
    }
  }
  return count;
}

String _stripIsolatedQuotes(String text) {
  return text.replaceAll(RegExp(r'["“”' r"''‘’]"), '');
}

/// 深度标点符号清洗与停顿 Token 映射。
String _normalizePunctuationAndTokens(String text) {
  String s = text;

  // 1. 过滤 Markdown 标记字符及无声特殊字符
  s = s.replaceAll(RegExp(r'[*#_`|\\^~=+<>$@&/]'), '');

  // 2. 过滤 Emoji 与未支持的特殊符号区间
  s = s.replaceAll(
    RegExp(
      r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}]',
      unicode: true,
    ),
    '',
  );

  // 3. 省略号与连续点 -> 映射为 ChatTTS 长停顿 [break_4]
  // 匹配形如：……、……、...、....、......、。。。
  s = s.replaceAll(RegExp(r'(?:…+|(?:\.{2,})|(?:。{2,}))'), '[break_4]');

  // 4. 破折号与长波浪线 -> 映射为 ChatTTS 短停顿 [break_2]
  s = s.replaceAll(RegExp(r'(?:—{1,}|-{2,}|～{1,})'), '[break_2]');

  // 5. 短停顿符号归一化：顿号、分号、英文逗号 -> 中文逗号
  s = s.replaceAll(RegExp(r'[、;；,]'), '，');

  // 6. 重复情感标点折叠（保留单字符语气）
  s = s.replaceAll(RegExp(r'[！!]{2,}'), '！');
  s = s.replaceAll(RegExp(r'[？\?]{2,}'), '？');
  s = s.replaceAll(RegExp(r'[，,]{2,}'), '，');
  s = s.replaceAll(RegExp(r'[。\.]{2,}'), '。');

  // 7. 问叹混合符号折叠
  s = s.replaceAll(RegExp(r'[？！\?!]{2,}'), '！');

  // 8. 英文问号/感叹号归一化为全角
  s = s.replaceAll('?', '？');
  s = s.replaceAll('!', '！');

  // 9. 规范化停顿标记周边的多余标点（例如 "[break_4]，" -> "[break_4]"）
  s = s.replaceAll(RegExp(r'(\[break_\d\])\s*[，,、]+'), r'$1');
  s = s.replaceAll(RegExp(r'[，,、]+\s*(\[break_\d\])'), r'$1');

  // 10. 首尾多余符号修剪（清理首尾的冗余逗号、句号及空白）
  s = s.replaceAll(RegExp(r'^[，,。\.\s]+'), '');
  s = s.replaceAll(RegExp(r'[，,\s]+$'), '');

  return s.trim();
}
