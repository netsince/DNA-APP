import 'settings_search_page.dart';

/// 搜索页里的一个分区（「常用」「最近使用」，或按分组归并的搜索结果）。
class SettingsSearchSection {
  const SettingsSearchSection({
    required this.title,
    required this.hits,
    this.hint,
  });

  final String title;
  final String? hint;
  final List<SettingsSearchHit> hits;
}

/// 「常用」在没有使用记录时兜底展示的条数。
const int kDefaultFrequentCount = 6;

/// 把搜索结果排成分区。抽成纯函数是为了能直接单测：
///
/// * **没有搜索词**：只给「常用」和「最近使用」两个分区（都来自使用记录）；
///   「常用」没有记录时用前几条入口兜底，避免一进搜索页就是空白。
/// * **有搜索词**：结果按所属设置分组归并，组序按结果在树里第一次出现的顺序
///   （树本身就是人工排过的顺序，不另外排序）。
List<SettingsSearchSection> buildSearchSections({
  required List<SettingsSearchHit> hits,
  required String query,
  required List<String> mostUsedIds,
  required List<String> recentIds,
  int limitPerSection = 6,
}) {
  final String q = query.trim().toLowerCase();

  if (q.isEmpty) {
    final Map<String, SettingsSearchHit> byEntryId =
        <String, SettingsSearchHit>{};
    for (final SettingsSearchHit hit in hits) {
      byEntryId.putIfAbsent(hit.entry.id, () => hit);
    }
    List<SettingsSearchHit> pick(List<String> ids) => <SettingsSearchHit>[
      for (final String id in ids)
        if (byEntryId[id] != null) byEntryId[id]!,
    ].take(limitPerSection).toList();

    List<SettingsSearchHit> frequent = pick(mostUsedIds);
    if (frequent.isEmpty) {
      // 新用户/清过记录：给几条最常见入口兜底，别让搜索页空着。
      frequent = hits.take(kDefaultFrequentCount).toList();
    }
    final List<SettingsSearchHit> recent = pick(recentIds);

    return <SettingsSearchSection>[
      if (frequent.isNotEmpty)
        SettingsSearchSection(title: '常用', hits: frequent),
      if (recent.isNotEmpty)
        SettingsSearchSection(
          title: '最近使用',
          hits: recent,
        ),
      if (recent.isEmpty)
        const SettingsSearchSection(
          title: '最近使用',
          hint: '打开过的设置会出现在这里。',
          hits: <SettingsSearchHit>[],
        ),
    ];
  }

  final List<SettingsSearchHit> matched = hits
      .where((SettingsSearchHit h) => h.haystack.contains(q))
      .toList();
  final Map<String, List<SettingsSearchHit>> byGroup =
      <String, List<SettingsSearchHit>>{};
  for (final SettingsSearchHit hit in matched) {
    byGroup.putIfAbsent(hit.group, () => <SettingsSearchHit>[]).add(hit);
  }
  return <SettingsSearchSection>[
    for (final MapEntry<String, List<SettingsSearchHit>> e in byGroup.entries)
      SettingsSearchSection(
        title: e.key,
        hits: e.value.take(limitPerSection).toList(),
        hint: e.value.length > limitPerSection
            ? '还有 ${e.value.length - limitPerSection} 条'
            : null,
      ),
  ];
}
