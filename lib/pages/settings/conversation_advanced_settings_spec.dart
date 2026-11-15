/// 设置 → 消息与高级（配置驱动版）。
///
/// 取代 `conversation_advanced_page.dart`：页面只剩一份声明，没有 build、
/// 没有 setState 镜像。
///
/// 行为对齐点（逐条对照旧页面）：
/// * 4 个开关的分组、顺序、图标与说明原样保留（「消息操作」在前，「文本处理」在后）。
/// * 4 个开关旧页面都是「改本地 state + saveXxx(一次 copyWith)」，所以声明成
///   默认的 immediate 写通道就等价，不需要 writeOverride。
/// * 宏变量写法说明与「管理清洗规则」都不是设置值：前者是参考手册（旧页面把它
///   放在开关旁会顶掉设置项的位置），后者是跳子页面。两者都声明成 [SettingAction]，
///   `searchable: false` —— 它们是装饰与跳转，不该在搜索里冒充一条设置。
library;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/setting_section.dart';
import 'regex_rules_page.dart';
import 'spec/settings_spec.dart';

/// 宏变量写法参考。
///
/// 抽成独立 builder 而不是写进某个开关的 hint：它讲的是**整组语法**，
/// 不是「解析动态占位符」这一个开关的补充说明，挂到开关上会让那一条
/// 看起来比别的设置项更重要。
Widget _macroHint() => const SettingHint(
  '常用写法：{{char}} 当前角色名，{{user}} 你的名字，'
  '{{roll 1-100}} 掷骰，{{random 甲|乙}} 随机二选一。',
  icon: Icons.help_outline,
);

/// 「管理清洗规则」入口（旧页面手写的描边 ListTile）。
///
/// 不走 [SettingTile]：那条描边是旧页面刻意用来把「去子页面」与「就地开关」
/// 在视觉上分开的，换成现成的 [SettingTile] 会丢掉这个区分。
Widget _regexRulesTile(BuildContext context, AppController controller) {
  return Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smAll,
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: AppAlpha.subtle),
        ),
      ),
      contentPadding: AppInsets.group,
      leading: const Icon(Icons.find_replace),
      title: const FitText('管理清洗规则'),
      subtitle: FitText('已配置 ${controller.settings.regexRules.length} 条'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RegexRulesPage(controller: controller),
        ),
      ),
    ),
  );
}

/// 消息与高级页的完整声明。
final FieldsEntry conversationAdvancedEntry = FieldsEntry(
  id: 'conversationAdvanced',
  groupId: SettingsGroupId.dataSecurity,
  icon: Icons.cleaning_services_outlined,
  title: '消息与高级',
  subtitle: '删除单条消息、剧情分叉、文本清洗',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'conversationAdvanced.messageActions',
      icon: Icons.touch_app_outlined,
      title: '消息操作',
      description: '在消息上长按或右键时，能做哪些事。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'conversationAdvanced.allowDeleteMessage',
          title: '删除单条消息',
          subtitle: '只删掉选中的那一条。',
          key: 'allowDeleteMessage',
          defaultValue: false,
        ),
        SettingToggle(
          id: 'conversationAdvanced.enableForking',
          title: '从任意处另起剧情',
          subtitle: '以某条消息为起点开一条新支线。',
          key: 'enableForking',
          defaultValue: false,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationAdvanced.textProcessing',
      icon: Icons.auto_fix_high_outlined,
      title: '文本处理',
      description: 'AI 发来的内容在显示前会做哪些加工。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'conversationAdvanced.enableCommandMacros',
          title: '解析动态占位符',
          // 旧页面这句带句号共 25 字，超过设置区副标题 24 字的上限；
          // 去掉句号即可等价保留全部信息，不必把它降级成常驻提示。
          subtitle: '支持 {{char}}、{{user}} 等写法',
          key: 'enableCommandMacros',
          defaultValue: true,
        ),
        SettingAction(
          id: 'conversationAdvanced.macroHint',
          title: '宏变量写法说明',
          searchable: false,
          builder: (BuildContext context, _) => _macroHint(),
        ),
        SettingToggle(
          id: 'conversationAdvanced.enableRegexReplacement',
          title: '正则文本清洗',
          subtitle: '按自定义规则过滤或替换消息内容。',
          key: 'enableRegexReplacement',
          defaultValue: true,
        ),
        SettingAction(
          id: 'conversationAdvanced.regexRules',
          title: '管理清洗规则',
          searchable: false,
          builder: _regexRulesTile,
        ),
      ],
    ),
  ],
);
