import 'package:dna/utils/message_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expandCommandMacros', () {
    test('基础宏', () {
      final String out = expandCommandMacros(
        '{{char}} 对 {{user}} 说',
        charName: '小美',
        userName: '阿强',
      );
      expect(out, '小美 对 阿强 说');
    });

    test('newline 与日期时间', () {
      final DateTime now = DateTime(2026, 8, 5, 14, 30, 5);
      final String out = expandCommandMacros(
        '日期{{date}}\n时间{{time}}',
        now: now,
      );
      expect(out, '日期2026-08-05\n时间14:30:05');
    });

    test('random 宏', () {
      final String out = expandCommandMacros('{{random:a|b|c}}');
      expect(['a', 'b', 'c'], contains(out));
    });

    test('pick 宏等价于 random', () {
      final String out = expandCommandMacros('{{pick:红|绿|蓝}}');
      expect(['红', '绿', '蓝'], contains(out));
    });

    test('roll 骰子宏结果为范围内数字', () {
      final String out = expandCommandMacros('{{roll:2d6}}');
      final int value = int.parse(out);
      expect(value, inInclusiveRange(2, 12));
    });

    test('未识别宏原样保留', () {
      final String out = expandCommandMacros('{{unknown}}');
      expect(out, '{{unknown}}');
    });
  });

  group('applyRegexRules', () {
    test('按规则替换', () {
      final List<RegexRule> rules = <RegexRule>[
        RegexRule(id: 'r1', pattern: r'(\S+)。\s*$', replacement: r'$1。'),
        RegexRule(id: 'r2', pattern: r'[ ]{2,}', replacement: ' '),
      ];
      expect(applyRegexRules('你好  世界  ', rules), '你好 世界 ');
    });

    test('非法正则被跳过不抛异常', () {
      final List<RegexRule> rules = <RegexRule>[
        RegexRule(id: 'bad', pattern: '(', replacement: 'x'),
        RegexRule(id: 'good', pattern: 'a', replacement: 'b'),
      ];
      expect(applyRegexRules('a', rules), 'b');
    });

    test('空规则列表原样返回', () {
      expect(applyRegexRules('abc', <RegexRule>[]), 'abc');
    });
  });

  group('RegexRule 序列化', () {
    test('toJson / fromJson 往返一致', () {
      final RegexRule rule = RegexRule(id: 'r1', pattern: 'a', replacement: 'b');
      final RegexRule back = RegexRule.fromJson(rule.toJson());
      expect(back.id, 'r1');
      expect(back.pattern, 'a');
      expect(back.replacement, 'b');
    });
  });
}
