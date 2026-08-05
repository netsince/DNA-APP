import 'dart:math';

/// 快速回复（Quick Reply）：聊天输入栏上方的一键发送按钮。
/// 点击后把 [message]（可含宏）填充到输入框并发送，省去重复输入。
class QuickReply {
  const QuickReply({
    required this.id,
    required this.label,
    required this.message,
    this.group,
  });

  final String id;

  /// 按钮上显示的文字。
  final String label;

  /// 点击后发送的消息内容，支持宏（见 [QuickReplyResolver.resolve]）。
  final String message;

  /// 分组名（用于在管理页与输入栏归类），空串表示不分组。
  final String? group;

  QuickReply copyWith({
    String? id,
    String? label,
    String? message,
    String? group,
  }) {
    return QuickReply(
      id: id ?? this.id,
      label: label ?? this.label,
      message: message ?? this.message,
      group: group ?? this.group,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'message': message,
      'group': group,
    };
  }

  static QuickReply fromJson(Map<String, dynamic> json) {
    return QuickReply(
      id: (json['id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      group: json['group'] as String?,
    );
  }
}

/// 快速回复宏解析器。点击发送前把消息模板中的宏替换成实际值。
/// 支持的宏：
/// - `{{char}}`：TA 角色名；
/// - `{{user}}`：用户人设名（Persona 名或占位）；
/// - `{{newline}}`：换行；
/// - `{{random:a|b|c}}`：从选项中随机选一个。
class QuickReplyResolver {
  static String resolve(
    String template, {
    String charName = '',
    String userName = '',
  }) {
    final Random random = Random();
    String out = template
        .replaceAll('{{char}}', charName)
        .replaceAll('{{user}}', userName)
        .replaceAll('{{newline}}', '\n');
    // 处理 {{random:a|b|c}}：最内层依次替换。
    final RegExp re = RegExp(r'\{\{random:([^}]*)\}\}');
    while (true) {
      final RegExpMatch? m = re.firstMatch(out);
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
    return out;
  }
}
