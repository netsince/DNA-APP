import 'package:dna/utils/light_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLightMarkdown', () {
    test('纯文本保持原样', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('你好世界');
      expect(runs, hasLength(1));
      expect(runs.single.text, '你好世界');
      expect(runs.single.bold, isFalse);
      expect(runs.single.italic, isFalse);
      expect(runs.single.code, isFalse);
      expect(runs.single.strike, isFalse);
    });

    test('加粗标记', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('前 **加粗** 后');
      expect(runs.map((LightMarkdownRun r) => r.text).toList(),
          <String>['前 ', '加粗', ' 后']);
      expect(runs[1].bold, isTrue);
      expect(runs[0].bold, isFalse);
    });

    test('斜体标记', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('*斜体*');
      expect(runs, hasLength(1));
      expect(runs.single.italic, isTrue);
    });

    test('行内代码标记', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('使用 `code` 高亮');
      expect(runs.map((LightMarkdownRun r) => r.text).toList(),
          <String>['使用 ', 'code', ' 高亮']);
      expect(runs[1].code, isTrue);
    });

    test('删除线标记', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('~~删除~~');
      expect(runs.map((LightMarkdownRun r) => r.text).toList(), <String>['删除']);
      expect(runs.single.strike, isTrue);
    });

    test('未闭合标记不崩溃，内容仍保留', () {
      final List<LightMarkdownRun> runs = parseLightMarkdown('**未闭合');
      expect(runs.map((LightMarkdownRun r) => r.text).join(), '未闭合');
    });
  });
}
