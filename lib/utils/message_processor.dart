import 'dart:math';

/// 一条正则替换规则：把 [pattern]（正则表达式）命中的内容替换为 [replacement]。
class RegexRule {
  const RegexRule({required this.id, required this.pattern, required this.replacement});

  final String id;
  final String pattern;
  final String replacement;

  RegexRule copyWith({String? id, String? pattern, String? replacement}) {
    return RegexRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      replacement: replacement ?? this.replacement,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'pattern': pattern,
        'replacement': replacement,
      };

  static RegexRule fromJson(Map<String, dynamic> json) {
    return RegexRule(
      id: (json['id'] as String?) ?? '',
      pattern: (json['pattern'] as String?) ?? '',
      replacement: (json['replacement'] as String?) ?? '',
    );
  }
}

/// 命令宏：支持在消息文本中使用的动态占位符。
///
/// 支持的宏：
/// - `{{char}}`：TA 角色名；
/// - `{{user}}`：用户人设名；
/// - `{{newline}}`：换行；
/// - `{{random:a|b|c}}` 或 `{{pick:a|b|c}}`：从选项中随机选一个；
/// - `{{roll:NdM}}`：掷 N 个 M 面骰子并求和；
/// - `{{date}}`：当前日期（yyyy-MM-dd）；
/// - `{{time}}`：当前时间（HH:mm:ss）。
String expandCommandMacros(
  String text, {
  String charName = '',
  String userName = '',
  DateTime? now,
}) {
  final DateTime dt = now ?? DateTime.now();
  final Random random = Random();
  String out = text
      .replaceAll('{{char}}', charName)
      .replaceAll('{{user}}', userName)
      .replaceAll('{{newline}}', '\n')
      .replaceAll('{{date}}', _formatDate(dt))
      .replaceAll('{{time}}', _formatTime(dt));

  // 选项类宏：{{random:a|b|c}} 与 {{pick:a|b|c}}
  final RegExp optionRe = RegExp(r'\{\{(?:random|pick):([^}]*)\}\}');
  while (true) {
    final RegExpMatch? m = optionRe.firstMatch(out);
    if (m == null) {
      break;
    }
    final List<String> options = m
        .group(1)!
        .split('|')
        .where((String o) => o.isNotEmpty)
        .toList();
    final String replacement =
        options.isEmpty ? '' : options[random.nextInt(options.length)];
    out = out.replaceFirst(m.group(0)!, replacement);
  }

  // 骰子宏：{{roll:NdM}}（例如 {{roll:2d6}}）
  final RegExp rollRe = RegExp(r'\{\{roll:(\d+)[dD](\d+)\}\}');
  while (true) {
    final RegExpMatch? m = rollRe.firstMatch(out);
    if (m == null) {
      break;
    }
    final int count = int.tryParse(m.group(1)!) ?? 1;
    final int sides = int.tryParse(m.group(2)!) ?? 0;
    if (count <= 0 || sides <= 0) {
      out = out.replaceFirst(m.group(0)!, '');
      continue;
    }
    int sum = 0;
    for (int i = 0; i < count; i++) {
      sum += random.nextInt(sides) + 1;
    }
    out = out.replaceFirst(m.group(0)!, '$sum');
  }

  return out;
}

/// 依次应用正则替换规则。
/// 规则中非法（无法编译）的正则会被跳过，不影响其余规则。
String applyRegexRules(String text, List<RegexRule> rules) {
  String out = text;
  for (final RegexRule rule in rules) {
    final String pattern = rule.pattern.trim();
    if (pattern.isEmpty) {
      continue;
    }
    try {
      out = out.replaceAll(RegExp(pattern), rule.replacement);
    } catch (_) {
      // 忽略非法正则
    }
  }
  return out;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _formatDate(DateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

String _formatTime(DateTime dt) =>
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
