import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/utils/novel_text_spans.dart';

/// `buildMessageTextSpan` 的行为锁。
///
/// 这个函数原本是 `chat_message_list.dart` 里的私有实现（207 行、零测试），
/// 负责三件事叠在一起：小说化排版（对白/旁白/括号注释）、轻量 Markdown、
/// 搜索命中高亮。搬出来之后先钉住最容易回归的三点。
Future<TextSpan> _span(
  WidgetTester tester,
  String text, {
  String query = '',
  Color highlight = const Color(0xFFFFF59D),
  Color? bubbleColor,
}) async {
  late TextSpan span;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          span = buildMessageTextSpan(
            context,
            text,
            query,
            highlight,
            bubbleColor: bubbleColor,
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return span;
}

String _flatten(InlineSpan span) {
  final StringBuffer buffer = StringBuffer();
  span.visitChildren((InlineSpan child) {
    if (child is TextSpan) {
      if (child.text != null) buffer.write(child.text);
      if (child.children != null && child.children!.isNotEmpty) {
        buffer.write(_flatten(child));
      }
    }
    return true;
  });
  return buffer.toString();
}

List<TextSpan> _all(InlineSpan span) {
  final List<TextSpan> out = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      out.add(s);
      for (final InlineSpan c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(span);
  return out;
}

void main() {
  testWidgets('文本保真：拼接后与输入一致（不吞字、不重复）', (WidgetTester tester) async {
    const String text = '「今天风很大。」她低声说（其实没人在意）。';
    final TextSpan span = await _span(tester, text);
    expect(_flatten(span), text);
  });

  testWidgets('搜索命中：命中的片段带高亮底色', (WidgetTester tester) async {
    const Color highlight = Color(0xFFFFF59D);
    final TextSpan span = await _span(
      tester,
      '今天风很大',
      query: '风',
      highlight: highlight,
    );
    final List<TextSpan> hit = _all(
      span,
    ).where((TextSpan s) => s.style?.backgroundColor == highlight).toList();
    expect(hit, isNotEmpty, reason: '命中片段必须带高亮底色');
    expect(hit.map((TextSpan s) => s.text).join(), contains('风'));
  });

  testWidgets('Markdown：**粗体** 标记被剥离，文本保真', (WidgetTester tester) async {
    final TextSpan span = await _span(tester, '这是**重点**内容');
    expect(_flatten(span), '这是重点内容');

    // 注意这里**没有**断言字重：普通叙述段落的字重由小说化排版层统一决定
    // （旁白 w400 / 对白 w500），会盖掉 markdown 给的 medium —— 也就是说
    // 「普通叙述里的 **粗体**」目前只剥标记、不变字重。这是搬迁前就有的行为，
    // 记在这里；要改是排版策略的事，不在本次搬迁范围内。
  });

  testWidgets('对白段落的字重来自小说化层（w500）', (WidgetTester tester) async {
    final TextSpan span = await _span(tester, '「你来了。」');
    final List<TextSpan> dialogue = _all(
      span,
    ).where((TextSpan s) => s.style?.fontWeight == FontWeight.w500).toList();
    expect(dialogue, isNotEmpty, reason: '对白应当是 medium 字重');
  });

  testWidgets('空文本不炸（返回空 span 链）', (WidgetTester tester) async {
    final TextSpan span = await _span(tester, '');
    expect(_flatten(span), '');
  });
}
