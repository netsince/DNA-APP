/// 语音合成前的文本清理。
///
/// 规则（优先级从高到低）：
/// 1. **括号内容永远不读**：移除所有中英文括号 `()` `（）` 及其内部内容（支持嵌套）。
/// 2. **引号内容优先**（仅当 [quoteOnly] 为 true）：若清理括号后仍存在成对的
///    中英文引号（`"` `“”` `'` `‘’`），则只读引号内的内容（多段用中文逗号连接）；
///    否则回退为读清理括号后的全文。
/// 3. [quoteOnly] 为 false 时，仅执行括号移除，直接读全文。
String cleanTtsText(String raw, {required bool quoteOnly}) {
  if (raw.isEmpty) return raw;
  final String noBracket = _removeBrackets(raw);
  if (!quoteOnly) return noBracket;
  final String quoted = _extractQuoted(noBracket);
  if (quoted.trim().isNotEmpty) return quoted;
  return noBracket;
}

/// 移除中英文括号（`()` `（）`）及其内部内容，支持嵌套。
String _removeBrackets(String s) {
  const List<(String, String)> pairs = <(String, String)>[
    ('(', ')'),
    ('（', '）'),
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

/// 提取成对引号（中英文 `"` `“”` `'` `‘’`）内的内容。
///
/// 返回多段引号内容用中文逗号连接后的字符串；无有效引号内容时返回空串。
String _extractQuoted(String s) {
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
    // 闭引号优先（匹配栈顶类型）：英文引号 `"` `'` 开闭是同一字符，
    // 若栈顶同类型则视为闭合。
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
  return chunks.join('，');
}
