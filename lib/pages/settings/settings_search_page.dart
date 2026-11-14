import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import 'settings_catalog.dart';

/// 一条可搜索的入口：分组名 + 条目 + 预处理过的检索串。
class _SearchHit {
  _SearchHit(this.group, this.entry)
      : haystack =
            '$group ${entry.title} ${entry.subtitle} ${entry.keywords}'
                .toLowerCase();

  final String group;
  final SettingsEntry entry;

  /// 小写化后的可检索文本，建索引时算一次，输入时只做 contains。
  final String haystack;
}

/// 设置搜索页：搜索 + 直达。
///
/// 索引直接来自 [settingsCatalog] —— 与设置主页渲染的是同一份数据，
/// 新增设置项不需要再维护第二张表。
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  /// 整页只建一次：目录在页面存活期间不变，按键时只做过滤。
  late final List<_SearchHit> _all = <_SearchHit>[
    for (final SettingsGroup group in settingsCatalog(widget.controller))
      for (final SettingsEntry entry in group.entries)
        if (entry.enabled) _SearchHit(group.title, entry),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String query = _query.trim().toLowerCase();
    final List<_SearchHit> results = query.isEmpty
        ? _all
        : _all
              .where((_SearchHit h) => h.haystack.contains(query))
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
                final _SearchHit hit = results[i];
                return Card(
                  child: ListTile(
                    leading: Icon(hit.entry.icon),
                    title: FitText(hit.entry.title),
                    subtitle: FitText('${hit.group} · ${hit.entry.subtitle}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => hit.entry.page(),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
