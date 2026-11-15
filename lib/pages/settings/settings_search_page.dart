/// 设置搜索：**字段级**索引 + 直达。
///
/// 索引直接来自 spec/settings_tree.dart —— 与设置主页渲染、页面字段渲染
/// 是同一棵树。新增一个字段，搜索自动能搜到，不需要再维护第二张表。
///
/// 覆盖两种粒度：
/// * 入口级（AI 服务与模型这类自定义页）→ 打开该页；
/// * 字段级（开场动画、温度这类具体设置项）→ 打开所属页，并把命中项展开、
///   滚到可见位置。
library;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/state_views.dart';
import 'settings_catalog.dart';
import 'spec/settings_fields_page.dart';
import 'spec/settings_spec.dart';
import 'spec/settings_tree.dart';

/// 一条搜索结果（入口级或字段级）。
class SettingsSearchHit {
  SettingsSearchHit.entry({required this.entry, required this.group})
    : section = null,
      item = null,
      haystack = <String>[
        group,
        entry.title,
        entry.subtitle,
        entry.id,
      ].join(' ').toLowerCase();

  SettingsSearchHit.field({
    required this.entry,
    required this.group,
    required SettingSectionSpec section,
    required SettingItemSpec item,
  }) : section = section,
       item = item,
       haystack = <String>[
         group,
         entry.title,
         section.title,
         ?section.description,
         ...item.searchTerms,
         item.id,
       ].join(' ').toLowerCase();

  final SettingsEntrySpec entry;
  final String group;
  final SettingSectionSpec? section;
  final SettingItemSpec? item;

  /// 预处理过的小写检索串：建索引时算一次，输入时只做 contains。
  final String haystack;

  bool get isField => item != null;

  /// 主标题：字段命中显示字段名，入口命中显示入口名。
  String get title => item?.title ?? entry.title;

  /// 副标题：字段命中显示所在位置。
  String get subtitle => item == null
      ? entry.subtitle
      : '${entry.title} · ${section?.title ?? ''}';

  IconData? get icon => entry.icon;
}

/// 建一次索引：入口 + 其下所有字段。
List<SettingsSearchHit> buildSettingsSearchIndex(AppController controller) {
  final SettingsRuntime runtime = SettingsRuntime(
    settings: controller.settings,
  );
  final List<SettingsSearchHit> hits = <SettingsSearchHit>[];
  // 树上的入口 + 不在主页但同样声明驱动的页面（采样参数、自由剪图、检查更新）。
  // 后者不列在主页，但用户搜「温度」「剪图」时应该能直接跳过去。
  final List<SettingsEntrySpec> entries = <SettingsEntrySpec>[
    ...settingsTree,
    ...settingsDetachedEntries,
  ];
  for (final SettingsEntrySpec spec in entries) {
    if (spec.visibleWhen != null && !spec.visibleWhen!(runtime)) continue;
    // 平台能力不满足的入口不参与搜索（与旧行为一致）。
    if (!settingsGateOpen(spec.gate)) continue;
    final String groupTitle = settingsGroupById(spec.groupId).title;
    hits.add(SettingsSearchHit.entry(entry: spec, group: groupTitle));
    if (spec is! FieldsEntry) continue;
    for (final SettingSectionSpec section in spec.sections) {
      for (final SettingItemSpec item in section.items) {
        if (!item.searchable) continue;
        if (!settingsItemVisible(item, runtime)) continue;
        hits.add(
          SettingsSearchHit.field(
            entry: spec,
            group: groupTitle,
            section: section,
            item: item,
          ),
        );
      }
    }
  }
  return hits;
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

  /// 整页只建一次：树在页面存活期间不变，按键时只做过滤。
  late final List<SettingsSearchHit> _all = buildSettingsSearchIndex(
    widget.controller,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(SettingsSearchHit hit) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => buildSettingsEntryPage(
          hit.entry,
          widget.controller,
          focusItemId: hit.item?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String query = _query.trim().toLowerCase();
    final List<SettingsSearchHit> results = query.isEmpty
        ? _all
        : _all
              .where((SettingsSearchHit h) => h.haystack.contains(query))
              .toList();

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
          ? AppEmptyState(
              icon: Icons.search_off_outlined,
              title: '没有找到「$_query」相关的设置',
              description: '换个说法试试，比如搜「主题」「音色」「备份」。',
            )
          : ListView.separated(
              padding: AppInsets.page,
              itemCount: results.length,
              separatorBuilder: (_, _) => AppSpacing.hXs,
              itemBuilder: (BuildContext context, int i) {
                final SettingsSearchHit hit = results[i];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      hit.isField ? Icons.tune : hit.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: FitText(hit.title),
                    subtitle: FitText('${hit.group} · ${hit.subtitle}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(hit),
                  ),
                );
              },
            ),
    );
  }
}
