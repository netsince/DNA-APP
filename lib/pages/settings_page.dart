// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/app_section.dart';
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
// 社区设置项:原样复用「岛」的子页,不重写。
import '../island_app/server_settings_body.dart';
import '../island_app/sponsor_body.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/liquid_glass.dart';

/// 设置主页。
///
/// **组织原则:按「用户想干什么」分组,而不是按技术模块分组。**
///
/// 本次重构(参见 DESIGN_SPEC.md 设置页章节):
/// * 删除 `conversation_settings_page` / `appearance_settings_page` 两个
///   「只列入口、自己不含任何设置项」的跳板页,所有入口直达最终页面;
/// * 导航深度从最多 6 层压到 4 层;
/// * 副标题一律**单行**,用 `maxLines: 1` 强制约束文案长度。
/// 设置栏目装配。
///
/// 滚动位置(跨子页面保留)住在装配闭包里,随壳常驻:
/// 切去别的栏目再回来,位置还在。
SectionPageData settingsSection(AppController controller) {
  // 结构守护测试(settings_structure_test)以此名字断言"滚动位置保留"。
  // ignore: no_leading_underscores_for_local_identifiers
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  return SectionPageData(
    section: AppSection.settings,
    contentMaxWidth: AppSize.settingsMaxWidth,
    appBar: (BuildContext context) => AppBar(
      title: const FitText('设置'),
      actions: <Widget>[
        IconButton(
          tooltip: '搜索设置',
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsSearchPage(controller: controller),
            ),
          ),
        ),
      ],
    ),
    body: (BuildContext context) =>
        SettingsBody(controller: controller, scrollOffset: _scrollOffset),
  );
}

/// 设置内容体:居中限宽的可滚动分组列表。
class SettingsBody extends StatelessWidget {
  const SettingsBody({
    super.key,
    required this.controller,
    required this.scrollOffset,
  });

  final AppController controller;

  /// 跨页面保留的滚动位置。
  ///
  /// 从子页返回时回到原来的位置,而不是跳回顶部 —— 主页有 7 个分组,
  /// 内容超过一屏,跳回顶部会让用户重新滚一遍。
  final ValueNotifier<double> scrollOffset;

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth > AppSize.settingsMaxWidth
            ? AppSize.settingsMaxWidth
            : constraints.maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w),
            child: _SettingsScrollBody(
              initialOffset: scrollOffset.value,
              onOffsetChanged: (double v) => scrollOffset.value = v,
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
                        AiServiceSettingsPage(controller: controller),
                      ),
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
                        PromptStrategyPage(controller: controller),
                      ),
                    ),
                    _Entry(
                      icon: Icons.send_outlined,
                      title: '回复与发送',
                      subtitle: '回车键行为、灵感生成与快速回复',
                      onTap: () => _push(
                        context,
                        ConversationSendPage(controller: controller),
                      ),
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
                        ConversationSummaryPage(controller: controller),
                      ),
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
                        context,
                        TtsSettingsPage(controller: controller),
                      ),
                    ),
                    _Entry(
                      icon: Icons.mic_none_outlined,
                      title: '语音输入',
                      subtitle: '用说话代替打字',
                      enabled: PlatformCapabilities.voiceInputSupported,
                      onTap: () => _push(
                        context,
                        VoiceInputSettingsPage(controller: controller),
                      ),
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
                        AppearanceDisplayPage(controller: controller),
                      ),
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
                        context,
                        DataSettingsPage(controller: controller),
                      ),
                    ),
                    _Entry(
                      icon: Icons.lock_outline,
                      title: '安全与隐私',
                      subtitle: '应用锁、删除前的二次确认',
                      onTap: () => _push(
                        context,
                        SecuritySettingsPage(controller: controller),
                      ),
                    ),
                    _Entry(
                      icon: Icons.cleaning_services_outlined,
                      title: '消息与高级',
                      subtitle: '删除单条消息、剧情分叉、文本清洗',
                      onTap: () => _push(
                        context,
                        ConversationAdvancedPage(controller: controller),
                      ),
                    ),
                  ],
                ),

                // ===== 7. 社区（DNAISLAND） =====
                // 服务器与赞助是从「岛」的设置里并过来的两件还活着的配置;
                // 岛的外观设置改的是已被主项目主题取代的旧主题,不再入口。
                // 整个社区功能在「界面与显示 → 启动与导航」里可以关掉,
                // 关掉后这一组设置也一并收起(开关本身不在这里,不会锁死)。
                if (controller.settings.enableCommunity)
                  _Group(
                    title: '社区（DNAISLAND）',
                    icon: Icons.explore_outlined,
                    entries: <_Entry>[
                      _Entry(
                        icon: Icons.dns_outlined,
                        title: '社区服务器',
                        subtitle: '社区后端地址，可用官方或自建',
                        onTap: () => _push(
                          context,
                          Scaffold(
                            appBar: AppBar(title: const Text('社区服务器')),
                            body: ServerSettingsBody(),
                          ),
                        ),
                      ),
                      _Entry(
                        icon: Icons.volunteer_activism_outlined,
                        title: '赞助社区',
                        subtitle: '支持 DNAISLAND 持续运转',
                        onTap: () => _push(
                          context,
                          Scaffold(
                            appBar: AppBar(title: const Text('赞助社区')),
                            body: SponsorBody(),
                          ),
                        ),
                      ),
                    ],
                  ),

                // ===== 8. 关于 =====
                _Group(
                  title: '关于',
                  icon: Icons.info_outline,
                  entries: <_Entry>[
                    _Entry(
                      icon: Icons.info_outline,
                      title: '版本与开源',
                      subtitle: '版本信息、项目成员与开源许可',
                      onTap: () => _push(context, const AboutPage()),
                    ),
                    _Entry(
                      icon: Icons.terminal_outlined,
                      title: '开发者选项',
                      subtitle: '命令控制台与调试工具',
                      onTap: () => _push(
                        context,
                        AdvancedSettingsPage(controller: controller),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
                    fontWeight: AppWeight.medium,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        LiquidGlass(
          tint: cs.primary,
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
          fontWeight: AppWeight.medium,
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

/// 设置搜索索引：设置主页所有入口 + 关键词别名。
/// 只做「找到入口」这一件事，具体开关仍然进各自的页面改。
class _SettingHit {
  const _SettingHit({
    required this.group,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.enabled,
    required this.builder,
  });

  final String group;
  final String title;
  final String subtitle;

  /// 额外关键词，方便用「深色」「气泡」「模型」这类词命中。
  final String keywords;
  final bool enabled;
  final Widget Function(BuildContext context, AppController controller) builder;

  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final String haystack =
        '$group $title $subtitle $keywords'.toLowerCase();
    return haystack.contains(q);
  }
}

/// 设置搜索页：搜索 + 直达。
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  List<_SettingHit> get _hits {
    final bool voice = PlatformCapabilities.voiceInputSupported;
    final bool tts = PlatformCapabilities.ttsSupported;
    final bool community = widget.controller.settings.enableCommunity;
    return <_SettingHit>[
      _SettingHit(
        group: 'AI 接入',
        title: 'AI 服务与模型',
        subtitle: '用哪个 AI、接口地址与密钥',
        keywords: '模型 接口 密钥 api 服务',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            AiServiceSettingsPage(controller: ctl),
      ),
      _SettingHit(
        group: '对话风格',
        title: '提示词策略',
        subtitle: 'AI 扮演的性格、语气与回复长度',
        keywords: '提示词 人设 长度 语气',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            PromptStrategyPage(controller: ctl),
      ),
      _SettingHit(
        group: '对话风格',
        title: '回复与发送',
        subtitle: '回车键行为、灵感生成与快速回复',
        keywords: '回车 灵感 快捷回复',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            ConversationSendPage(controller: ctl),
      ),
      _SettingHit(
        group: '记忆与上下文',
        title: '剧情摘要与上下文',
        subtitle: 'AI 记得多久、世界书怎么生效',
        keywords: '记忆 摘要 上下文 世界书',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            ConversationSummaryPage(controller: ctl),
      ),
      _SettingHit(
        group: '角色语音',
        title: '语音合成与背景音乐',
        subtitle: '让角色开口说话，或自带背景音乐',
        keywords: '语音 朗读 配音 tts 音色 背景音乐',
        enabled: tts,
        builder: (BuildContext c, AppController ctl) =>
            TtsSettingsPage(controller: ctl),
      ),
      _SettingHit(
        group: '角色语音',
        title: '语音输入',
        subtitle: '用说话代替打字',
        keywords: '麦克风 录音 转文字',
        enabled: voice,
        builder: (BuildContext c, AppController ctl) =>
            VoiceInputSettingsPage(controller: ctl),
      ),
      _SettingHit(
        group: '界面与显示',
        title: '外观与聊天界面',
        subtitle: '明暗主题、强调色、气泡与半屏模式',
        keywords: '深色 浅色 主题 配色 强调色 气泡 半屏 字号',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            AppearanceDisplayPage(controller: ctl),
      ),
      _SettingHit(
        group: '数据与安全',
        title: '备份与还原',
        subtitle: '定期备份、换设备时迁移',
        keywords: '备份 还原 迁移 导出 导入',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            DataSettingsPage(controller: ctl),
      ),
      _SettingHit(
        group: '数据与安全',
        title: '安全与隐私',
        subtitle: '应用锁、删除前的二次确认',
        keywords: '锁 密码 隐私 确认',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            SecuritySettingsPage(controller: ctl),
      ),
      _SettingHit(
        group: '数据与安全',
        title: '消息与高级',
        subtitle: '删除单条消息、剧情分叉、文本清洗',
        keywords: '删除 分叉 清洗 高级',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            ConversationAdvancedPage(controller: ctl),
      ),
      if (community)
        _SettingHit(
          group: '社区（DNAISLAND）',
          title: '社区服务器',
          subtitle: '社区后端地址，可用官方或自建',
          keywords: '社区 岛 服务器 地址',
          enabled: true,
          builder: (BuildContext c, AppController ctl) => Scaffold(
            appBar: AppBar(title: const Text('社区服务器')),
            body: const ServerSettingsBody(),
          ),
        ),
      if (community)
        _SettingHit(
          group: '社区（DNAISLAND）',
          title: '赞助社区',
          subtitle: '支持 DNAISLAND 持续运转',
          keywords: '赞助 捐赠',
          enabled: true,
          builder: (BuildContext c, AppController ctl) => Scaffold(
            appBar: AppBar(title: const Text('赞助社区')),
            body: const SponsorBody(),
          ),
        ),
      _SettingHit(
        group: '关于',
        title: '版本与开源',
        subtitle: '版本信息、项目成员与开源许可',
        keywords: '版本 关于 许可 开源 作者',
        enabled: true,
        builder: (BuildContext c, AppController ctl) => const AboutPage(),
      ),
      _SettingHit(
        group: '关于',
        title: '开发者选项',
        subtitle: '命令控制台与调试工具',
        keywords: '开发者 调试 日志 控制台',
        enabled: true,
        builder: (BuildContext c, AppController ctl) =>
            AdvancedSettingsPage(controller: ctl),
      ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<_SettingHit> results = _hits.where((_SettingHit h) => h.enabled && h.matches(_query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索设置（如：深色、气泡、音色、备份）',
            border: InputBorder.none,
          ),
          onChanged: (String v) => setState(() => _query = v),
        ),
      ),
      body: results.isEmpty
          ? Center(
              child: Text(
                '没有找到「$_query」相关的设置',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: AppInsets.page,
              itemCount: results.length,
              separatorBuilder: (_, _) => AppSpacing.hXs,
              itemBuilder: (BuildContext context, int i) {
                final _SettingHit h = results[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.chevron_right),
                    title: FitText(h.title),
                    subtitle: FitText('${h.group} · ${h.subtitle}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext c) =>
                            h.builder(c, widget.controller),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}