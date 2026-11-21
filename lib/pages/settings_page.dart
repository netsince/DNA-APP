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
    contentMaxWidth: AppSize.pageMaxWidth,
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

/// 一个设置分组：分组小标题 + 直接贴在 surface 上的行。
///
/// 分组内容来自 [settingsCatalog]，这里只负责画、不持有数据。
///
/// ## 为什么不再「每组一张卡」（审计 3.3 / 4.2）
///
/// 卡片是「可整体操作的内容单元」的容器。设置分组不是那种单元 —— 它就是
/// 一串同构的行。给每组套一张卡，等于用容器（描边/圆角/卡片间距）代替
/// **字号阶 + 间距**来表达层级，结果一屏七个框，谁也不是重点。
///
/// 现在层级由三件事建立：小标题的字号与语义色（`titleSmall` + `onSurfaceVariant`，
/// `primary` 只留给可交互元素）、组间距、以及组内至多一根 Divider。
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onOpen});

  final SettingsGroup group;
  final ValueChanged<SettingsEntry> onOpen;

  /// 行内文字的左边缘：行内边距 + leading 图标 + `ListTile` 默认的
  /// horizontalTitleGap（正好等于 [AppSpacing.lg]）。
  ///
  /// Divider 用这个缩进，才能和行标题对齐而不是从屏幕边走。
  static const double _rowTextIndent =
      AppSpacing.lg + AppSize.iconCard + AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 分组小标题：左缘对齐**行的 leading 图标**（AppSpacing.lg = 16）。
        // 选「与图标同列」而不是「与行标题同列」：图标是一条稳定的竖轨，
        // 不依赖 ListTile 内部的 horizontalTitleGap；行标题比它再右移 16，
        // 读起来仍是同一列（图标列）对齐。
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                group.icon,
                size: AppSize.iconCard,
                color: cs.onSurfaceVariant,
              ),
              AppSpacing.wSm,
              Expanded(
                child: FitText(
                  group.title,
                  style: ts.titleSmall?.copyWith(
                    fontWeight: AppWeight.medium,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 行直接贴在 surface 上；组内最多一根 Divider，缩进与行文字对齐。
        for (int i = 0; i < group.entries.length; i++) ...<Widget>[
          if (i > 0)
            Divider(
              height: 1,
              indent: _rowTextIndent,
              color: cs.outlineVariant,
            ),
          _EntryTile(
            entry: group.entries[i],
            onTap: () => onOpen(group.entries[i]),
          ),
        ],
        // 组间距现在是唯一的分组信号，所以比原来的卡片间距大一档。
        AppSpacing.hXl,
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
        color: on ? cs.onSurfaceVariant : cs.outline.withValues(alpha: AppAlpha.half),
      ),
      onTap: on ? onTap : null,
    );
  }
}

