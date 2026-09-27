// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/widgets/setting_section.dart';

import 'widgets.dart';

/// DeepSeek 深度思考模式(仅当前服务商为 DeepSeek 时展示)。
///
/// 强度选项的取值 'low' / 'high' / 'max' 原样透传给 `saveDeepseekThinking`,
/// 未做任何改动。
class AiThinkingSection extends StatelessWidget {
  const AiThinkingSection({
    super.key,
    required this.enabled,
    required this.effort,
    required this.onEnabledChanged,
    required this.onEffortChanged,
  });

  final bool enabled;
  final String effort;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onEffortChanged;

  /// 强度取值顺序(与 `AppController.saveDeepseekThinking` 的合法集合一致)。
  static const List<String> efforts = <String>['low', 'high', 'max'];

  static String _effortLabel(String effort) {
    switch (effort) {
      case 'low':
        return '低';
      case 'high':
        return '高';
      default:
        return '最高';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingSection(
      icon: Icons.psychology_outlined,
      title: '深度思考模式',
      description: '回答前先打草稿，复杂问题更稳。',
      children: <Widget>[
        SettingSwitch(
          title: '回答前先思考',
          subtitle: '等待时间会稍长一些',
          value: enabled,
          onChanged: onEnabledChanged,
        ),
        if (enabled) ...<Widget>[
          AiChoiceGroup<String>(
            options: efforts,
            selected: effort,
            labelOf: _effortLabel,
            subtitle: '强度越高越费时间，也越贵。',
            onSelected: onEffortChanged,
          ),
        ],
      ],
    );
  }
}
