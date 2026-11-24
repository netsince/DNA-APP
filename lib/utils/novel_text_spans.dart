import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'light_markdown.dart';

/// 一条消息正文的**富文本排版**：小说化分段（对白/旁白/括号注释三种墨色）、
/// 轻量 Markdown（粗体/斜体/删除线/行内代码）、以及搜索命中高亮。
///
/// 从 `chat_message_list.dart` 搬出来：它是这 200 行的纯函数（只吃 context + 文本 +
/// 查询词 + 高亮色），留在那个一千行的列表文件里既不好找也不好测。
/// 搬出来也是下一步「主气泡拆成独立 widget」的前置 —— 气泡要搬，这个函数得先能独立引用。
///
/// [bubbleColor] 是气泡底色：墨色按它的明暗取反（深色气泡配浅墨、亮色气泡配深墨），
/// 不传时按主题亮暗判断。
TextSpan buildMessageTextSpan(
  BuildContext context,
  String text,
  String query,
  Color highlightColor, {
  Color? bubbleColor,
}) {
  final ColorScheme colorScheme = Theme.of(context).colorScheme;

  final bool isLightBg = bubbleColor != null
      ? FitText.isLightBackground(bubbleColor, colorScheme.surface)
      : Theme.of(context).brightness == Brightness.light;

  // 气泡底色来自角色卡取色,可能非常亮(甚至接近纯白),也可能很深。
  // 之前正文写死 colorScheme.onSurface:深色模式 + 亮色气泡就是
  // 「白底白字」,浅色模式 + 深色气泡则是「黑底黑字」,两种情况都
  // 看不清。这里按气泡明暗取墨色(半透明气泡先与页面底色合成),
  // 保证正文、旁白、括号注释三个层次都能反色。
  final Color ink = FitText.inkFor(
    bubbleColor ?? colorScheme.surface,
    colorScheme.surface,
  );

  // base 是所有派生样式的源头(代码块、搜索高亮、根 span 都从它
  // copyWith)。**必须在这里就带上墨色**:否则那些没有显式指定颜色
  // 的片段会继承主题色 —— 亮色气泡 + 深色主题时就是「白字配白底」。
  final TextStyle base = DefaultTextStyle.of(context).style.copyWith(
    height: AppLineHeight.body,
    color: ink,
  );

  final Color dialogueColor = ink;

  final Color narrationColor = ink.withValues(
    alpha: isLightBg ? 0.88 : 0.82,
  );

  final Color parenColor = ink.withValues(alpha: isLightBg ? 0.72 : 0.65);

  final TextStyle dialogueStyle = base.copyWith(
    fontWeight: AppWeight.medium,
    color: dialogueColor,
  );

  final TextStyle narrationStyle = base.copyWith(
    fontWeight: FontWeight.normal,
    color: narrationColor,
  );

  final TextStyle parenStyle = base.copyWith(
    fontWeight: FontWeight.normal,
    color: parenColor,
  );

  // 检查是否为括号（中英文）
  bool isOpeningBracket(String char) => char == '(' || char == '（';
  bool isClosingBracket(String char) => char == ')' || char == '）';

  // 检查是否为对话引号开始/结束
  bool isOpeningQuote(String char) => char == '“' || char == '「' || char == '『' || char == '"';
  bool isClosingQuote(String char, String openChar) {
    if (openChar == '“') return char == '”';
    if (openChar == '「') return char == '」';
    if (openChar == '『') return char == '』';
    if (openChar == '"') return char == '"';
    return false;
  }

  // 构建括号片段（支持中英文括号）
  List<InlineSpan> buildParenthesisSpans(String input, TextStyle normalStyle, TextStyle pStyle) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int i = 0;
    while (i < input.length) {
      int openIndex = -1;
      for (int j = i; j < input.length; j++) {
        if (isOpeningBracket(input[j])) {
          openIndex = j;
          break;
        }
      }

      if (openIndex == -1) {
        spans.add(TextSpan(text: input.substring(i), style: normalStyle));
        break;
      }

      if (openIndex > i) {
        spans.add(TextSpan(text: input.substring(i, openIndex), style: normalStyle));
      }

      int closeIndex = openIndex + 1;
      int depth = 1;
      while (closeIndex < input.length && depth > 0) {
        if (isOpeningBracket(input[closeIndex])) {
          depth++;
        } else if (isClosingBracket(input[closeIndex])) {
          depth--;
        }
        closeIndex++;
      }

      if (depth == 0) {
        spans.add(TextSpan(text: input.substring(openIndex, closeIndex), style: pStyle));
        i = closeIndex;
      } else {
        spans.add(TextSpan(text: input.substring(openIndex), style: normalStyle));
        break;
      }
    }
    return spans;
  }

  // 对一段纯文本应用「小说化引号分级」+「括号弱化」
  List<InlineSpan> buildNovelizedSpans(String input, TextStyle defaultStyle) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int i = 0;
    while (i < input.length) {
      int quoteStart = -1;
      String openQuote = '';
      for (int j = i; j < input.length; j++) {
        if (isOpeningQuote(input[j])) {
          quoteStart = j;
          openQuote = input[j];
          break;
        }
      }

      if (quoteStart == -1) {
        // 剩余全部为旁白/叙述
        spans.addAll(buildParenthesisSpans(input.substring(i), narrationStyle, parenStyle));
        break;
      }

      if (quoteStart > i) {
        // 引号前为旁白/叙述
        spans.addAll(buildParenthesisSpans(input.substring(i, quoteStart), narrationStyle, parenStyle));
      }

      int quoteEnd = quoteStart + 1;
      while (quoteEnd < input.length) {
        if (isClosingQuote(input[quoteEnd], openQuote)) {
          quoteEnd++;
          break;
        }
        quoteEnd++;
      }

      final String quoteSegment = input.substring(quoteStart, quoteEnd);
      spans.addAll(buildParenthesisSpans(quoteSegment, dialogueStyle, parenStyle));
      i = quoteEnd;
    }
    return spans;
  }

  // 对一段文本应用「搜索高亮」
  List<InlineSpan> buildPlainSpans(String input, TextStyle style) {
    if (query.isEmpty) {
      return buildNovelizedSpans(input, style);
    }
    final String lowerText = input.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    int start = 0;
    final List<InlineSpan> spans = <InlineSpan>[];
    while (true) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.addAll(buildNovelizedSpans(input.substring(start), style));
        break;
      }
      if (index > start) {
        spans.addAll(buildNovelizedSpans(input.substring(start, index), style));
      }
      spans.add(
        TextSpan(
          text: input.substring(index, index + query.length),
          style: style.copyWith(
            backgroundColor: highlightColor,
            fontWeight: AppWeight.medium,
          ),
        ),
      );
      start = index + query.length;
    }
    return spans;
  }

  final TextStyle codeStyle = base.copyWith(
    fontFamily: 'monospace',
    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: AppAlpha.a60),
    fontSize: (base.fontSize ?? 14) * 0.92,
  );

  // 依据轻量 Markdown 标记生成带样式的片段，并在此基础上叠加小说化排版/搜索高亮。
  final List<InlineSpan> children = <InlineSpan>[];
  for (final LightMarkdownRun run in parseLightMarkdown(text)) {
    TextStyle style = base;
    if (run.code) {
      style = codeStyle;
    } else {
      if (run.bold) style = style.copyWith(fontWeight: AppWeight.medium);
      if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (run.strike) style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    children.addAll(buildPlainSpans(run.text, style));
  }
  return TextSpan(children: children, style: base);
}
