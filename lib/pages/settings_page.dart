import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'settings/advanced_settings_page.dart';
import 'settings/ai_service_settings_page.dart';
import 'settings/appearance_settings_page.dart';
import 'settings/conversation_settings_page.dart';
import 'settings/voice_input_settings_page.dart';
import 'settings/tts_settings_page.dart';
import 'settings/tts_cache_page.dart';
import 'settings/data_settings_page.dart';
import 'settings/security_settings_page.dart';
import 'settings/about_page.dart';
import 'package:dna/widgets/fit_text.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('设置')),
      drawer: AppDrawer(controller: controller, current: AppSection.settings),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: <Widget>[
                  _MenuItem(
                    icon: Icons.memory,
                    title: 'AI 服务',
                    subtitle: 'API 连接与模型选择',
                    onTap: () => _push(context, AiServiceSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.chat_bubble_outline,
                    title: '对话与策略',
                    subtitle: '提示词、灵感、摘要及发送策略',
                    onTap: () => _push(context, ConversationSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.lock_outline,
                    title: '安全与隐私',
                    subtitle: '生物识别验证保护',
                    onTap: () => _push(context, SecuritySettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.palette_outlined,
                    title: '外观与体验',
                    subtitle: '应用图标、动画及引导流程',
                    onTap: () => _push(context, AppearanceSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.mic_outlined,
                    title: '语音输入',
                    subtitle: '离线语音转文字（需下载模型）',
                    onTap: () => _push(context, VoiceInputSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.record_voice_over_outlined,
                    title: '语音合成',
                    subtitle: '角色语音播放（端侧 TTS）',
                    onTap: () => _push(context, TtsSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.cleaning_services_outlined,
                    title: '语音缓存',
                    subtitle: '查看并清理已合成音频缓存',
                    onTap: () => _push(context, const TtsCachePage()),
                  ),
                  _MenuItem(
                    icon: Icons.storage_outlined,
                    title: '数据管理',
                    subtitle: '备份、恢复与导出导入',
                    onTap: () => _push(context, DataSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.warning_amber_outlined,
                    title: '高级',
                    subtitle: '命令系统',
                    onTap: () => _push(context, AdvancedSettingsPage(controller: controller)),
                  ),
                  _MenuItem(
                    icon: Icons.info_outline,
                    title: '关于',
                    subtitle: '作者、官方网站与第三方开源组件',
                    onTap: () => _push(context, const AboutPage()),
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: FitText(title),
      subtitle: FitText(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
