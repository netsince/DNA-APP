// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/app_drawer.dart';
import 'settings/advanced_settings_page.dart';
import 'settings/ai_service_settings_page.dart';
import 'settings/appearance_settings_page.dart';
import 'settings/conversation_settings_page.dart';
import 'settings/voice_input_settings_page.dart';
import 'settings/tts_settings_page.dart';
import 'settings/data_settings_page.dart';
import 'settings/security_settings_page.dart';
import 'settings/about_page.dart';
import 'package:dna/widgets/fit_text.dart';

/// 设置主页面。
///
/// 结构化模块分组：
/// 1. 核心 AI 与对话策略
/// 2. 视觉外观与安全隐私
/// 3. 语音与多模态交互
/// 4. 系统数据与关于
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppScaffold(
      controller: controller,
      current: AppSection.settings,
      appBar: AppBar(title: const FitText('设置')),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: <Widget>[
                  // ===== 1. 核心 AI 与对话策略 =====
                  _SectionHeader(title: '核心 AI 与对话', icon: Icons.psychology_outlined),
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: <Widget>[
                        _MenuItem(
                          icon: Icons.memory,
                          title: 'AI 服务与模型',
                          subtitle: '服务商切换、Base URL、API Key 与生效模型',
                          onTap: () => _push(context, AiServiceSettingsPage(controller: controller)),
                        ),
                        const Divider(height: 1, indent: 56),
                        _MenuItem(
                          icon: Icons.chat_bubble_outline,
                          title: '对话与策略',
                          subtitle: '提示词策略、剧情摘要、上下文预算、回复模式与正则清洗',
                          onTap: () => _push(context, ConversationSettingsPage(controller: controller)),
                        ),
                      ],
                    ),
                  ),

                  // ===== 2. 视觉外观与安全隐私 =====
                  _SectionHeader(title: '视觉与安全', icon: Icons.palette_outlined),
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: <Widget>[
                        _MenuItem(
                          icon: Icons.color_lens_outlined,
                          title: '外观与体验',
                          subtitle: '明暗主题、专属强调色、桌面图标、启动动画与聊天气泡',
                          onTap: () => _push(context, AppearanceSettingsPage(controller: controller)),
                        ),
                        const Divider(height: 1, indent: 56),
                        _MenuItem(
                          icon: Icons.security_outlined,
                          title: '安全与隐私',
                          subtitle: '应用锁生物识别验证、实体删除防误触保护',
                          onTap: () => _push(context, SecuritySettingsPage(controller: controller)),
                        ),
                      ],
                    ),
                  ),

                  // ===== 3. 语音与多模态交互 =====
                  _SectionHeader(title: '语音与多模态', icon: Icons.mic_none_outlined),
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: <Widget>[
                        _MenuItem(
                          icon: Icons.record_voice_over_outlined,
                          title: '端侧语音合成 (TTS)',
                          subtitle: '本地角色朗读、台词过滤、全局音色 Seed 与音频缓存',
                          enabled: PlatformCapabilities.ttsSupported,
                          onTap: () => _push(context, TtsSettingsPage(controller: controller)),
                        ),
                        const Divider(height: 1, indent: 56),
                        _MenuItem(
                          icon: Icons.mic_outlined,
                          title: '离线语音输入 (ASR)',
                          subtitle: '麦克风语音转文字、本地离线识别模型管理',
                          enabled: PlatformCapabilities.voiceInputSupported,
                          onTap: () => _push(context, VoiceInputSettingsPage(controller: controller)),
                        ),
                      ],
                    ),
                  ),

                  // ===== 4. 系统数据与关于 =====
                  _SectionHeader(title: '系统与数据', icon: Icons.folder_outlined),
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: <Widget>[
                        _MenuItem(
                          icon: Icons.storage_outlined,
                          title: '数据管理',
                          subtitle: '每日自动备份、ZIP 全量备份还原、JSON 单对话导出',
                          onTap: () => _push(context, DataSettingsPage(controller: controller)),
                        ),
                        const Divider(height: 1, indent: 56),
                        _MenuItem(
                          icon: Icons.terminal_outlined,
                          title: '高级命令系统',
                          subtitle: '开发者指令与高级调试控制台',
                          onTap: () => _push(context, AdvancedSettingsPage(controller: controller)),
                        ),
                        const Divider(height: 1, indent: 56),
                        _MenuItem(
                          icon: Icons.info_outline,
                          title: '关于与开源',
                          subtitle: '版本信息、项目成员、社区链接与开源许可证',
                          onTap: () => _push(context, const AboutPage()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          FitText(
            title,
            style: ts.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled
              ? cs.primaryContainer.withValues(alpha: 0.6)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? cs.onPrimaryContainer : cs.outline,
        ),
      ),
      title: FitText(
        title,
        style: ts.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: enabled ? null : cs.outline,
        ),
      ),
      subtitle: FitText(
        subtitle,
        style: ts.bodySmall?.copyWith(
          color: enabled ? cs.onSurfaceVariant : cs.outline,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: enabled ? cs.onSurfaceVariant : cs.outline.withValues(alpha: 0.5),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
