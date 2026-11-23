/// 设置 → 剧情摘要与上下文（配置驱动版）。
///
/// 取代 `conversation_summary_page.dart`：8 个手写控件（1 开关 + 5 步进 + 2 文本框）
/// 与 `_autoSummary` / `_turns` / `_words` / `_ctxMessages` 及两个
/// `TextEditingController` 全部变成声明，页面不再自己维护镜像状态。
///
/// ## helper 文案为什么有的进 subtitle、有的进 hint
///
/// 渲染器对折叠数值项取 helper 的规则是 `item.hint ?? item.subtitle`：
/// * 写 subtitle —— 收起态不显示，展开后才当 helper 出现在控件下方，与旧页面
///   的 `CollapsibleNumberSetting(helper: ...)` 逐像素一致；
/// * 写 hint —— 展开时同样是 helper，但渲染器还会在条目下方再画一行常驻
///   提示（`SettingHint`），于是文案会出现两次。
///
/// 所以凡旧页面 helper 不超过 24 字（设置区副标题上限）的一律写 subtitle，
/// 超过的才退到 hint —— 让「长说明只在展开后出现」这条设计规矩尽量多成立。
///
/// ## 写入时机
///
/// 折叠控件旧页面是「每动一格就 saveXxx」，声明里写 onRelease 是因为渲染器
/// 改成拖动中只更新本地草稿、松手才落盘（同一个 `onChangeEnd` 通道）。
/// 文本框两者一致：回车/失焦才提交，声明为 onSubmit。
///
/// ## 没有 writeOverride
///
/// 旧页面的 saveSummarySettings / saveMaxContextMessages / saveLoreBudgetTokens
/// 等全是「copyWith 一个字段 + 落盘」；其中的 clamp 边界（0..1000 / 0..100000 /
/// 0..1000000 等）都宽于或等于这里声明的 min/max，控件本身已经把值限制在
/// 声明的范围内，因此走 `patchSettings` 与旧路径落盘结果相同。
library;

import 'package:flutter/material.dart';

import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';

/// 世界书注入的定位说明（词条本身在世界页编辑）。
Widget _loreScopeHint() => const SettingHint(
  '词条的编写与管理在「世界」页；这里只控制全局的生效范围与容量。',
  icon: Icons.info_outline,
);

/// 剧情摘要与上下文页的完整声明。
final FieldsEntry conversationSummaryEntry = FieldsEntry(
  id: 'conversationSummary',
  groupId: SettingsGroupId.memory,
  icon: Icons.history_edu_outlined,
  title: '剧情摘要与上下文',
  subtitle: 'AI 记得多久、世界书怎么生效',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'conversationSummary.trigger',
      icon: Icons.history_edu_outlined,
      title: '剧情摘要',
      description: '对话变长后，让 AI 记住前文。',
      items: <SettingItemSpec>[
        // 旧页面拨这个开关时会连 summaryTurnInterval 一起写回（saveSummarySettings
        // 一次写两个字段），但写的是当前值 —— 只改一个键落盘结果相同。
        SettingToggle(
          id: 'conversationSummary.autoSummaryPrompt',
          title: '自动生成摘要',
          subtitle: '达到下面的条件时，提示 AI 总结前文。',
          key: 'autoSummaryPrompt',
          defaultValue: true,
        ),
        SettingInt(
          id: 'conversationSummary.summaryTurnInterval',
          title: '达到多少轮对话时摘要',
          hint: '计数的是对话轮数（一问一答算两轮），不是消息条数。',
          key: 'summaryTurnInterval',
          defaultValue: 200,
          min: 10,
          max: 1000,
          step: 10,
          unit: '轮',
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingInt(
          id: 'conversationSummary.summaryWordThreshold',
          title: '新增多少字后摘要',
          hint: '与上面的轮数条件满足任意一个就会触发。填 0 表示只看轮数。',
          key: 'summaryWordThreshold',
          defaultValue: 6000,
          min: 0,
          max: 50000,
          step: 500,
          unit: '字',
          zeroLabel: '不限',
          saveMode: SettingsSaveMode.onRelease,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationSummary.history',
      icon: Icons.inventory_2_outlined,
      title: '携带多少历史',
      description: '发给 AI 的对话范围，超出从最早的开始丢。',
      items: <SettingItemSpec>[
        SettingInt(
          id: 'conversationSummary.maxContextMessages',
          title: '最多带上多少条消息',
          subtitle: '只影响发送给 AI 的范围，聊天记录本身不会丢。',
          key: 'maxContextMessages',
          defaultValue: 120,
          min: 0,
          max: 500,
          step: 10,
          unit: '条',
          zeroLabel: '不限',
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingInt(
          id: 'conversationSummary.maxContextTokens',
          title: '最多占用多少记忆容量',
          hint:
              'Token 是 AI 计量文字用量的单位，1 个汉字约等于 1 个 Token。'
              '范围太大或太小都不合适，拿不准就保持默认。',
          key: 'maxContextTokens',
          defaultValue: 8000,
          min: 0,
          max: 100000,
          unit: 'Token',
          zeroLabel: '不限',
          editor: NumberEditor.textField,
          saveMode: SettingsSaveMode.onSubmit,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationSummary.lore',
      icon: Icons.public_outlined,
      title: '世界书注入',
      description: '控制世界观词条被激活后如何注入对话。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'conversationSummary.loreScopeHint',
          title: '世界书注入范围说明',
          searchable: false,
          builder: (BuildContext context, _) => _loreScopeHint(),
        ),
        // 这两项旧页面没传 step，由折叠组件按范围自动推导成 1（divisions 30 / 50）；
        // 这里用 SettingInt 的默认 step: 1，滑块刻度数与旧页面相同。
        SettingInt(
          id: 'conversationSummary.loreStickyRounds',
          title: '词条命中后持续几轮',
          hint: '词条被关键词命中后，在接下来这几轮内持续生效，避免中途「忘设定」。',
          key: 'loreStickyRounds',
          defaultValue: 3,
          min: 0,
          max: 30,
          unit: '轮',
          zeroLabel: '不持续',
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingInt(
          id: 'conversationSummary.loreMaxEntries',
          title: '一次最多注入几条词条',
          subtitle: '注入太多会冲淡人设，建议保持默认的少量。',
          key: 'loreMaxEntries',
          defaultValue: 8,
          min: 0,
          max: 50,
          unit: '条',
          zeroLabel: '不限',
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingInt(
          id: 'conversationSummary.loreBudgetTokens',
          title: '世界书最多占用多少容量',
          subtitle: '超出时优先丢掉优先级低的词条。',
          key: 'loreBudgetTokens',
          defaultValue: 0,
          min: 0,
          max: 100000,
          unit: 'Token',
          zeroLabel: '不限',
          editor: NumberEditor.textField,
          saveMode: SettingsSaveMode.onSubmit,
        ),
      ],
    ),
  ],
);
