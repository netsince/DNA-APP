/// 设置区的**唯一数据源**：设置主页、搜索、以及页面的字段渲染都读这一棵树。
///
/// ## 三条身份约定（为本地化留的路）
///
/// 1. **分组用 [SettingsGroupId] 当身份，不用分组名当 key。**
///    分组名是显示文案（会翻译），标识是身份（永不翻译）。从前这里是
///    `Map<String, IconData>{'AI 接入': …}` 加一个中文字符串数组排序 ——
///    一旦出英文界面，Map 的 key 全部失配、排序退化成原样。
/// 2. **入口与字段也各有稳定 id**（`id: 'security.requireAuthForApp'`），
///    搜索定位、测试断言、埋点都用它，跟文案无关。
/// 3. 显示文案只参与搜索匹配，不参与任何身份判断。
///
/// ## 迁移状态
///
/// * 已转成字段声明（[FieldsEntry]）：外观与聊天界面、回复与发送、剧情摘要与
///   上下文、消息与高级、安全与隐私。
/// * 仍是手写页面（[CustomEntry]）：AI 服务、提示词策略、语音合成、语音输入、
///   备份还原、社区两项、关于、开发者选项。
/// * 不在设置主页出现、但同样由声明驱动：[settingsDetachedEntries]
///   （从开发者选项/命令进入的页面）。
library;

import 'package:flutter/material.dart';

import 'package:dna/pages/settings/server_settings_body.dart';
import 'package:dna/pages/settings/sponsor_body.dart';
import '../../../state/app_controller.dart';
import 'settings_spec.dart';

import '../about_page.dart';
import '../advanced_settings_page.dart';
import '../ai_service_settings_page.dart';
import '../appearance_display_spec.dart';
import '../conversation_advanced_settings_spec.dart';
import '../conversation_prompt_strategy_page.dart';
import '../conversation_send_spec.dart';
import '../conversation_summary_settings_spec.dart';
import '../data_settings_page.dart';
import '../free_image_settings_spec.dart';
import '../sampler_settings_spec.dart';
import '../security_settings_spec.dart';
import '../storage_settings_page.dart';
import '../tts_settings_spec.dart';
import '../update_settings_spec.dart';

/// 全部设置分组，**列表顺序即界面顺序**。
///
/// 本地化时只改 [SettingsGroupSpec.title]，id、顺序、图标都不动。
const List<SettingsGroupSpec> settingsGroups = <SettingsGroupSpec>[
  SettingsGroupSpec(
    id: SettingsGroupId.ai,
    title: 'AI 接入',
    icon: Icons.memory,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.dialogue,
    title: '对话风格',
    icon: Icons.chat_bubble_outline,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.memory,
    title: '记忆与上下文',
    icon: Icons.psychology_outlined,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.voice,
    title: '角色语音',
    icon: Icons.record_voice_over_outlined,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.appearance,
    title: '界面与显示',
    icon: Icons.palette_outlined,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.dataSecurity,
    title: '数据与安全',
    icon: Icons.shield_outlined,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.community,
    title: '社区（DNAISLAND）',
    icon: Icons.explore_outlined,
  ),
  SettingsGroupSpec(
    id: SettingsGroupId.about,
    title: '关于',
    icon: Icons.info_outline,
  ),
];

/// 按 id 取分组定义（渲染、搜索都走这里，不再各自维护映射）。
SettingsGroupSpec settingsGroupById(SettingsGroupId id) =>
    settingsGroups.firstWhere((SettingsGroupSpec g) => g.id == id);

/// 全部设置入口。
final List<SettingsEntrySpec> settingsTree = <SettingsEntrySpec>[
  CustomEntry(
    id: 'aiService',
    groupId: SettingsGroupId.ai,
    icon: Icons.smart_toy_outlined,
    title: 'AI 服务与模型',
    subtitle: '用哪个 AI、接口地址与密钥',
    builder: (AppController c) => AiServiceSettingsPage(controller: c),
  ),
  CustomEntry(
    id: 'promptStrategy',
    groupId: SettingsGroupId.dialogue,
    icon: Icons.tune,
    title: '提示词策略',
    subtitle: 'AI 扮演的性格、语气与回复长度',
    builder: (AppController c) => PromptStrategyPage(controller: c),
  ),
  conversationSendEntry,
  conversationSummaryEntry,
  ttsEntry,
  bgmEntry,
  appearanceEntry,
  CustomEntry(
    id: 'dataBackup',
    groupId: SettingsGroupId.dataSecurity,
    icon: Icons.storage_outlined,
    title: '备份与还原',
    subtitle: '定期备份、换设备时迁移',
    builder: (AppController c) => DataSettingsPage(controller: c),
  ),
  CustomEntry(
    id: 'storageUsage',
    groupId: SettingsGroupId.dataSecurity,
    icon: Icons.pie_chart_outline,
    title: '存储空间',
    subtitle: '占了多少、都花在哪儿',
    builder: (AppController c) => StorageSettingsPage(controller: c),
  ),
  securityEntry,
  conversationAdvancedEntry,
  CustomEntry(
    id: 'communityServer',
    groupId: SettingsGroupId.community,
    icon: Icons.dns_outlined,
    title: '社区服务器',
    subtitle: '社区后端地址，可用官方或自建',
    visibleWhen: (SettingsRuntime r) => r.settings.enableCommunity,
    builder: (AppController c) => Scaffold(
      appBar: AppBar(title: const Text('社区服务器')),
      body: const ServerSettingsBody(),
    ),
  ),
  CustomEntry(
    id: 'communitySponsor',
    groupId: SettingsGroupId.community,
    icon: Icons.volunteer_activism_outlined,
    title: '赞助社区',
    subtitle: '支持 DNAISLAND 持续运转',
    visibleWhen: (SettingsRuntime r) => r.settings.enableCommunity,
    builder: (AppController c) => Scaffold(
      appBar: AppBar(title: const Text('赞助社区')),
      body: const SponsorBody(),
    ),
  ),
  CustomEntry(
    id: 'about',
    groupId: SettingsGroupId.about,
    icon: Icons.info_outline,
    title: '版本与开源',
    subtitle: '版本信息、项目成员与开源许可',
    builder: (AppController c) => AboutPage(controller: c),
  ),
  CustomEntry(
    id: 'developer',
    groupId: SettingsGroupId.about,
    icon: Icons.terminal_outlined,
    title: '开发者选项',
    subtitle: '命令控制台与调试工具',
    // 默认藏起来：在「关于 → 版本号」连点 10 次才出现，再连点 10 次收起。
    // 里面有命令控制台和「清空全部数据」，不该让普通用户顺手点进去。
    visibleWhen: (SettingsRuntime r) => r.settings.developerOptionsUnlocked,
    builder: (AppController c) => AdvancedSettingsPage(controller: c),
  ),
];

/// 不在设置主页出现、但同样是「声明驱动」的字段页。
///
/// 它们的入口在开发者选项/命令里（自由剪图、检查更新、采样参数由 AI 服务页进入）。之所以要在这里登记，
/// 是因为「待迁移清单」的守卫测试要能看见它们 —— 否则这些 key 会被误判成
/// 「既没进树、又没登记」，跑去给它们补一份界面。
final List<FieldsEntry> settingsDetachedEntries = <FieldsEntry>[
  freeImageCropEntry,
  updateCheckEntry,
  samplerEntry,
];
