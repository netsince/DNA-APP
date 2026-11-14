// 设置目录：**设置入口的唯一数据源**。
//
// 设置主页按它渲染分组与入口，搜索页按它建索引。两边读同一份数据，
// 所以新增入口只需在这里加一条 —— 不会出现「界面有、搜索搜不到」。
//
// ## 已知边界：这不是「设置搜索」，是「入口搜索」
//
// 这里索引的粒度是**入口页**，不是页面里的具体设置项。用户搜「开场动画」
// 找不到，因为那是「外观与聊天界面 → 启动与导航」里的一个开关，目录里只有
// 「外观与聊天界面」这一条。
//
// keywords 是手写的别名，属于第二份知识：写得再全也只是猜用户会怎么搜。
// 真正的设置搜索要求**设置项本身是声明式数据**（每项自带标题/关键词/读写方式），
// 由同一份声明同时驱动渲染与检索；那是一次结构性重构，不在本次范围。
//
// 组织原则：按「用户想干什么」分组，而不是按技术模块分组。
// 本次重构（参见 DESIGN_SPEC.md 设置页章节）：
// * 删除 conversation_settings_page / appearance_settings_page 两个
//   「只列入口、自己不含任何设置项」的跳板页，所有入口直达最终页面；
// * 导航深度从最多 6 层压到 4 层；
// * 副标题一律**单行**，用 maxLines: 1 强制约束文案长度。

import 'package:flutter/material.dart';

import '../../island_app/server_settings_body.dart';
import '../../island_app/sponsor_body.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import 'about_page.dart';
import 'advanced_settings_page.dart';
import 'ai_service_settings_page.dart';
import 'appearance_display_page.dart';
import 'conversation_advanced_page.dart';
import 'conversation_prompt_strategy_page.dart';
import 'conversation_send_page.dart';
import 'conversation_summary_page.dart';
import 'data_settings_page.dart';
import 'security_settings_page.dart';
import 'tts_settings_page.dart';
import 'voice_input_settings_page.dart';

/// 一个设置入口的描述。
///
/// [page] 是页面工厂而不是 `onTap`：只依赖 controller、不捕获 BuildContext，
/// 这样目录才能脱离某个具体的 build 被枚举（搜索页要用的就是这一点）。
///
/// [keywords] 是搜索别名，界面上不显示。
class SettingsEntry {
  const SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.page,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String keywords;
  final Widget Function() page;

  /// 平台能力不满足时入口仍然显示（置灰），但不参与搜索。
  final bool enabled;
}

/// 一个设置分组：标题 + 一张卡片里的若干入口。
class SettingsGroup {
  const SettingsGroup({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<SettingsEntry> entries;
}

/// 当前可用的设置分组，顺序即界面顺序。
List<SettingsGroup> settingsCatalog(AppController controller) {
  return <SettingsGroup>[
    SettingsGroup(
      title: 'AI 接入',
      icon: Icons.memory,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.smart_toy_outlined,
          title: 'AI 服务与模型',
          subtitle: '用哪个 AI、接口地址与密钥',
          keywords: '模型 接口 密钥 api 服务 服务商',
          page: () => AiServiceSettingsPage(controller: controller),
        ),
      ],
    ),
    SettingsGroup(
      title: '对话风格',
      icon: Icons.chat_bubble_outline,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.tune,
          title: '提示词策略',
          subtitle: 'AI 扮演的性格、语气与回复长度',
          keywords: '提示词 人设 长度 语气 策略',
          page: () => PromptStrategyPage(controller: controller),
        ),
        SettingsEntry(
          icon: Icons.send_outlined,
          title: '回复与发送',
          subtitle: '回车键行为、灵感生成与快速回复',
          keywords: '回车 灵感 快捷回复 发送',
          page: () => ConversationSendPage(controller: controller),
        ),
      ],
    ),
    SettingsGroup(
      title: '记忆与上下文',
      icon: Icons.psychology_outlined,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.history_edu_outlined,
          title: '剧情摘要与上下文',
          subtitle: 'AI 记得多久、世界书怎么生效',
          keywords: '记忆 摘要 上下文 世界书',
          page: () => ConversationSummaryPage(controller: controller),
        ),
      ],
    ),
    SettingsGroup(
      title: '角色语音',
      icon: Icons.record_voice_over_outlined,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.volume_up_outlined,
          title: '语音合成与背景音乐',
          subtitle: '让角色开口说话，或自带背景音乐',
          keywords: '语音 朗读 配音 tts 音色 背景音乐 音乐',
          enabled: PlatformCapabilities.ttsSupported,
          page: () => TtsSettingsPage(controller: controller),
        ),
        SettingsEntry(
          icon: Icons.mic_none_outlined,
          title: '语音输入',
          subtitle: '用说话代替打字',
          keywords: '麦克风 录音 转文字 语音输入',
          enabled: PlatformCapabilities.voiceInputSupported,
          page: () => VoiceInputSettingsPage(controller: controller),
        ),
      ],
    ),
    SettingsGroup(
      title: '界面与显示',
      icon: Icons.palette_outlined,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.dashboard_customize_outlined,
          title: '外观与聊天界面',
          subtitle: '明暗主题、强调色、气泡与半屏模式',
          keywords: '深色 浅色 主题 配色 强调色 气泡 半屏 字号 外观',
          page: () => AppearanceDisplayPage(controller: controller),
        ),
      ],
    ),
    SettingsGroup(
      title: '数据与安全',
      icon: Icons.shield_outlined,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.storage_outlined,
          title: '备份与还原',
          subtitle: '定期备份、换设备时迁移',
          keywords: '备份 还原 迁移 导出 导入',
          page: () => DataSettingsPage(controller: controller),
        ),
        SettingsEntry(
          icon: Icons.lock_outline,
          title: '安全与隐私',
          subtitle: '应用锁、删除前的二次确认',
          keywords: '锁 密码 隐私 确认 应用锁',
          page: () => SecuritySettingsPage(controller: controller),
        ),
        SettingsEntry(
          icon: Icons.cleaning_services_outlined,
          title: '消息与高级',
          subtitle: '删除单条消息、剧情分叉、文本清洗',
          keywords: '删除 分叉 清洗 高级 消息',
          page: () => ConversationAdvancedPage(controller: controller),
        ),
      ],
    ),
    // 服务器与赞助是从「岛」的设置里并过来的两件还活着的配置；
    // 岛的外观设置改的是已被主项目主题取代的旧主题，不再入口。
    // 整个社区功能可以在「界面与显示 → 启动与导航」里关掉，
    // 关掉后这一组也一并收起（开关本身不在这里，不会锁死）。
    if (controller.settings.enableCommunity)
      SettingsGroup(
        title: '社区（DNAISLAND）',
        icon: Icons.explore_outlined,
        entries: <SettingsEntry>[
          SettingsEntry(
            icon: Icons.dns_outlined,
            title: '社区服务器',
            subtitle: '社区后端地址，可用官方或自建',
            keywords: '社区 岛 服务器 地址',
            page: () => Scaffold(
              appBar: AppBar(title: const Text('社区服务器')),
              body: const ServerSettingsBody(),
            ),
          ),
          SettingsEntry(
            icon: Icons.volunteer_activism_outlined,
            title: '赞助社区',
            subtitle: '支持 DNAISLAND 持续运转',
            keywords: '赞助 捐赠',
            page: () => Scaffold(
              appBar: AppBar(title: const Text('赞助社区')),
              body: const SponsorBody(),
            ),
          ),
        ],
      ),
    SettingsGroup(
      title: '关于',
      icon: Icons.info_outline,
      entries: <SettingsEntry>[
        SettingsEntry(
          icon: Icons.info_outline,
          title: '版本与开源',
          subtitle: '版本信息、项目成员与开源许可',
          keywords: '版本 关于 许可 开源 作者 成员',
          page: () => const AboutPage(),
        ),
        SettingsEntry(
          icon: Icons.terminal_outlined,
          title: '开发者选项',
          subtitle: '命令控制台与调试工具',
          keywords: '开发者 调试 日志 控制台',
          page: () => AdvancedSettingsPage(controller: controller),
        ),
      ],
    ),
  ];
}
