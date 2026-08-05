/// 一段带内联样式标记的文本片段。
class LightMarkdownRun {
  const LightMarkdownRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;
}

/// 轻量 Markdown 解析：支持 **加粗**、*斜体*、`行内代码`、~~删除线~~。
///
/// 仅做内联样式，不做标题/列表/块引用等块级转换，以免破坏现有排版。
/// 若标记未成对闭合，则保持为普通文本，不影响整体显示。
List<LightMarkdownRun> parseLightMarkdown(String text) {
  final List<LightMarkdownRun> runs = <LightMarkdownRun>[];
  final StringBuffer sb = StringBuffer();
  bool bold = false;
  bool italic = false;
  bool code = false;
  bool strike = false;

  void flush() {
    final String s = sb.toString();
    if (s.isNotEmpty) {
      runs.add(LightMarkdownRun(
        s,
        bold: bold,
        italic: italic,
        code: code,
        strike: strike,
      ));
      sb.clear();
    }
  }

  int i = 0;
  final int n = text.length;
  while (i < n) {
    if (code) {
      final int closeIdx = text.indexOf('`', i);
      if (closeIdx == -1) {
        sb.write(text.substring(i));
        i = n;
      } else {
        sb.write(text.substring(i, closeIdx));
        flush();
        code = false;
        i = closeIdx + 1;
      }
      continue;
    }
    if (text.startsWith('`', i)) {
      flush();
      code = true;
      i += 1;
      continue;
    }
    if (text.startsWith('~~', i)) {
      flush();
      strike = !strike;
      i += 2;
      continue;
    }
    if (text.startsWith('**', i)) {
      flush();
      bold = !bold;
      i += 2;
      continue;
    }
    if (text.startsWith('*', i)) {
      flush();
      italic = !italic;
      i += 1;
      continue;
    }
    sb.write(text[i]);
    i += 1;
  }
  flush();
  return runs;
}
