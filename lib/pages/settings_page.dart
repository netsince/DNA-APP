// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/app_drawer.dart';
import 'settings/advanced_settings_page.dart';
import 'settings/ai_service_settings_page.dart';
import 'settings/appearance_display_page.dart';
import 'settings/conversation_advanced_page.dart';
import 'settings/conversation_prompt_strategy_page.dart';
import 'settings/conversation_send_page.dart';
import 'settings/conversation_summary_page.dart';
import 'settings/data_settings_page.dart';
import 'settings/security_settings_page.dart';
import 'settings/tts_settings_page.dart';
import 'settings/voice_input_settings_page.dart';
import 'settings/about_page.dart';
import 'package:dna/widgets/fit_text.dart';

/// 设置主页。
///
/// **组织原则:按「用户想干什么」分组,而不是按技术模块分组。**
///
/// 本次重构(参见 DESIGN_SPEC.md 设置页章节):
/// * 删除 `conversation_settings_page` / `appearance_settings_page` 两个
///   「只列入口、自己不含任何设置项」的跳板页,所有入口直达最终页面;
/// * 导航深度从最多 6 层压到 4 层;
/// * 副标题一律**单行**,用 `maxLines: 1` 强制约束文案长度。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  /// 跨页面保留的滚动位置。
  ///
  /// 从子页返回时回到原来的位置,而不是跳回顶部 —— 主页有 7 个分组,
  /// 内容超过一屏,跳回顶部会让用户重新滚一遍。
  static final ValueNotifier<double> _scrollOffset =
      ValueNotifier<double>(0);

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      controller: controller,
      current: AppSection.settings,
      appBar: AppBar(title: const FitText('设置')),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w =
              constraints.maxWidth > AppSize.settingsMaxWidth
                  ? AppSize.settingsMaxWidth
                  : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: _SettingsScrollBody(
                initialOffset: _scrollOffset.value,
                onOffsetChanged: (double v) => _scrollOffset.value = v,
                children: <Widget>[
                  // ===== 1. AI 接入 =====
                  _Group(
                    title: 'AI 接入',
                    icon: Icons.memory,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.smart_toy_outlined,
                        title: 'AI 服务与模型',
                        subtitle: '用哪个 AI、接口地址与密钥',
                        onTap: () => _push(
                            context,
                            AiServiceSettingsPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 2. 对话风格 =====
                  _Group(
                    title: '对话风格',
                    icon: Icons.chat_bubble_outline,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.tune,
                        title: '提示词策略',
                        subtitle: 'AI 扮演的性格、语气与回复长度',
                        onTap: () => _push(
                            context,
                            PromptStrategyPage(controller: controller)),
                      ),
                      _Entry(
                        icon: Icons.send_outlined,
                        title: '回复与发送',
                        subtitle: '回车键行为、灵感生成与快速回复',
                        onTap: () => _push(
                            context,
                            ConversationSendPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 3. 记忆与上下文 =====
                  _Group(
                    title: '记忆与上下文',
                    icon: Icons.psychology_outlined,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.history_edu_outlined,
                        title: '剧情摘要与上下文',
                        subtitle: 'AI 记得多久、世界书怎么生效',
                        onTap: () => _push(
                            context,
                            ConversationSummaryPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 4. 角色语音 =====
                  _Group(
                    title: '角色语音',
                    icon: Icons.record_voice_over_outlined,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.volume_up_outlined,
                        title: '语音合成与背景音乐',
                        subtitle: '让角色开口说话，或自带背景音乐',
                        enabled: PlatformCapabilities.ttsSupported,
                        onTap: () => _push(
                            context, TtsSettingsPage(controller: controller)),
                      ),
                      _Entry(
                        icon: Icons.mic_none_outlined,
                        title: '语音输入',
                        subtitle: '用说话代替打字',
                        enabled: PlatformCapabilities.voiceInputSupported,
                        onTap: () => _push(context,
                            VoiceInputSettingsPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 5. 界面与显示 =====
                  _Group(
                    title: '界面与显示',
                    icon: Icons.palette_outlined,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.dashboard_customize_outlined,
                        title: '外观与聊天界面',
                        subtitle: '明暗主题、强调色、气泡与半屏模式',
                        onTap: () => _push(
                            context,
                            AppearanceDisplayPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 6. 数据与安全 =====
                  _Group(
                    title: '数据与安全',
                    icon: Icons.shield_outlined,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.storage_outlined,
                        title: '备份与还原',
                        subtitle: '定期备份、换设备时迁移',
                        onTap: () => _push(
                            context, DataSettingsPage(controller: controller)),
                      ),
                      _Entry(
                        icon: Icons.lock_outline,
                        title: '安全与隐私',
                        subtitle: '应用锁、删除前的二次确认',
                        onTap: () => _push(context,
                            SecuritySettingsPage(controller: controller)),
                      ),
                      _Entry(
                        icon: Icons.cleaning_services_outlined,
                        title: '消息与高级',
                        subtitle: '删除单条消息、剧情分叉、文本清洗',
                        onTap: () => _push(context,
                            ConversationAdvancedPage(controller: controller)),
                      ),
                    ],
                  ),

                  // ===== 7. 关于 =====
                  _Group(
                    title: '关于',
                    icon: Icons.info_outline,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.info_outline,
                        title: '版本与开源',
                        subtitle: '版本信息、项目成员与开源许可',
                        onTap: () =>
                            _push(context, const AboutPage()),
                      ),
                      _Entry(
                        icon: Icons.terminal_outlined,
                        title: '开发者选项',
                        subtitle: '命令控制台与调试工具',
                        onTap: () => _push(context,
                            AdvancedSettingsPage(controller: controller)),
                      ),
                    ],
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

/// 可保留滚动位置的列表体。
class _SettingsScrollBody extends StatefulWidget {
  const _SettingsScrollBody({
    required this.initialOffset,
    required this.onOffsetChanged,
    required this.children,
  });

  final double initialOffset;
  final ValueChanged<double> onOffsetChanged;
  final List<Widget> children;

  @override
  State<_SettingsScrollBody> createState() => _SettingsScrollBodyState();
}

class _SettingsScrollBodyState extends State<_SettingsScrollBody> {
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    // 还原上次离开时的位置(有上限保护:内容变短时不越界)。
    _ctrl = ScrollController(initialScrollOffset: widget.initialOffset);
    _ctrl.addListener(() => widget.onOffsetChanged(_ctrl.offset));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _ctrl,
      padding: AppInsets.page,
      children: widget.children,
    );
  }
}

/// 一个设置分组:标题 + 一张卡片。
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: AppSize.iconCard, color: cs.primary),
              AppSpacing.wSm,
              Expanded(
                child: FitText(
                  title,
                  style: ts.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: <Widget>[
              for (int i = 0; i < entries.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, indent: AppSize.iconInline * 3),
                _EntryTile(entry: entries[i]),
              ],
            ],
          ),
        ),
        AppSpacing.hLg,
      ],
    );
  }
}

/// 一个设置入口的数据。
class _Entry {
  const _Entry({
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
}

/// 设置入口行。
///
/// 设计要点(参考 Operit 的 `CompactSettingsItem`):
/// * **裸图标**,不用 38×38 色块 —— 色块视觉重量过大,一屏多个会显得吵;
/// * 副标题 **`maxLines: 1`** 强制单行,用代码逼着文案写短;
/// * 内边距收紧,一屏能看到更多入口。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;
    final bool on = entry.enabled;

    return ListTile(
      enabled: on,
      contentPadding: AppInsets.tile,
      leading: Icon(
        entry.icon,
        size: AppSize.iconCard,
        color: on ? cs.primary : cs.outline,
      ),
      title: FitText(
        entry.title,
        style: ts.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: on ? null : cs.outline,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: FitText(
        entry.subtitle,
        style: ts.bodySmall?.copyWith(
          color: on ? cs.onSurfaceVariant : cs.outline,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: on ? cs.onSurfaceVariant : cs.outline.withValues(alpha: 0.5),
      ),
      onTap: on ? entry.onTap : null,
    );
  }
}
