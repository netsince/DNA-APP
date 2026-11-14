// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';
import 'settings/settings_catalog.dart';
import 'settings/settings_search_page.dart';

/// 设置主页。
///
/// 分组与入口的内容全部来自 [settingsCatalog]（单一数据源），
/// 这里只负责装配外壳：顶栏（含搜索入口）+ 可保留滚动位置的内容体。
/// 分组原则与设计约束见 settings/settings_catalog.dart。
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
                for (final SettingsGroup group in settingsCatalog(controller))
                  _GroupTile(
                    group: group,
                    onOpen: (SettingsEntry entry) =>
                        _push(context, entry.page()),
                  ),              ],
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

/// 一个设置分组：标题 + 一张卡片。
///
/// 分组内容来自 [settingsCatalog]，这里只负责画、不持有数据。
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onOpen});

  final SettingsGroup group;
  final ValueChanged<SettingsEntry> onOpen;

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
              Icon(group.icon, size: AppSize.iconCard, color: cs.primary),
              AppSpacing.wSm,
              Expanded(
                child: FitText(
                  group.title,
                  style: ts.labelLarge?.copyWith(
                    fontWeight: AppWeight.medium,
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
              for (int i = 0; i < group.entries.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, indent: AppSize.iconInline * 3),
                _EntryTile(
                  entry: group.entries[i],
                  onTap: () => onOpen(group.entries[i]),
                ),
              ],
            ],
          ),
        ),
        AppSpacing.hLg,
      ],
    );
  }
}

/// 设置入口行。
///
/// 设计要点(参考 Operit 的 `CompactSettingsItem`):
/// * **裸图标**,不用 38×38 色块 —— 色块视觉重量过大,一屏多个会显得吵;
/// * 副标题 **`maxLines: 1`** 强制单行,用代码逼着文案写短;
/// * 内边距收紧,一屏能看到更多入口。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final SettingsEntry entry;

  final VoidCallback onTap;

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
      onTap: on ? onTap : null,
    );
  }
}

