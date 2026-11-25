import 'package:dna/pages/settings/settings_search_page.dart';
import 'package:dna/pages/settings/settings_search_sections.dart';
import 'package:dna/pages/settings/settings_usage_store.dart';
import 'package:dna/pages/settings/spec/settings_spec.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索页的分区（常用 / 最近使用 / 按分组归并）与使用记录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SettingsEntrySpec entry(String id, {String title = 'AI 服务与模型'}) =>
      CustomEntry(
        id: id,
        groupId: SettingsGroupId.ai,
        title: title,
        subtitle: '副标题',
        builder: (_) => const SizedBox.shrink(),
      );

  SettingsSearchHit hit(String id, {String group = 'AI 接入'}) =>
      SettingsSearchHit.entry(entry: entry(id), group: group);

  group('使用记录', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SettingsUsageStore.instance.debugReset();
    });

    test('记录次数与最近使用顺序', () async {
      final SettingsUsageStore store = SettingsUsageStore.instance;
      await store.ensureLoaded();
      await store.record('a', now: DateTime(2026, 1, 1, 10));
      await store.record('b', now: DateTime(2026, 1, 1, 11));
      await store.record('a', now: DateTime(2026, 1, 1, 12));

      expect(store.countOf('a'), 2);
      expect(store.countOf('b'), 1);
      expect(store.mostUsed().first, 'a');
      expect(store.recentlyUsed().first, 'a', reason: '最近一次打开的是 a');
    });

    test('写进 SharedPreferences 后能读回来', () async {
      final SettingsUsageStore store = SettingsUsageStore.instance;
      await store.ensureLoaded();
      await store.record('x', now: DateTime(2026, 1, 2));
      // 模拟重启：重置内存态后再加载
      store.debugReset();
      await store.ensureLoaded();
      expect(store.countOf('x'), 1);
      expect(store.recentlyUsed().first, 'x');
    });

    test('记录坏了不影响使用（当作空）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings_usage_v1': '这不是 JSON{',
      });
      final SettingsUsageStore store = SettingsUsageStore.instance;
      await store.ensureLoaded();
      expect(store.mostUsed(), isEmpty);
    });
  });

  group('分区编排', () {
    test('没有搜索词：给出「常用」与「最近使用」两个分区', () {
      final List<SettingsSearchHit> hits = <SettingsSearchHit>[
        hit('a'),
        hit('b'),
        hit('c'),
      ];
      final List<SettingsSearchSection> sections = buildSearchSections(
        hits: hits,
        query: '',
        mostUsedIds: <String>['b', 'a'],
        recentIds: <String>['c'],
      );
      expect(sections.map((SettingsSearchSection s) => s.title).toList(),
          <String>['常用', '最近使用']);
      expect(sections[0].hits.map((SettingsSearchHit h) => h.entry.id).toList(),
          <String>['b', 'a']);
      expect(sections[1].hits.single.entry.id, 'c');
    });

    test('没有使用记录时「常用」有兜底，「最近使用」给提示', () {
      final List<SettingsSearchHit> hits = <SettingsSearchHit>[
        hit('a'),
        hit('b'),
      ];
      final List<SettingsSearchSection> sections = buildSearchSections(
        hits: hits,
        query: '',
        mostUsedIds: const <String>[],
        recentIds: const <String>[],
      );
      expect(sections.first.title, '常用');
      expect(sections.first.hits, isNotEmpty, reason: '新用户也要有东西可点');
      final SettingsSearchSection recent = sections
          .firstWhere((SettingsSearchSection s) => s.title == '最近使用');
      expect(recent.hits, isEmpty);
      expect(recent.hint, isNotNull);
    });

    test('有搜索词：结果按设置分组归并', () {
      final SettingsSearchHit h1 = hit('a', group: '界面与显示');
      final SettingsSearchHit h2 = hit('b', group: '界面与显示');
      final SettingsSearchHit h3 = hit('c', group: 'AI 接入');
      final List<SettingsSearchSection> sections = buildSearchSections(
        hits: <SettingsSearchHit>[h1, h2, h3],
        query: '服务',
        mostUsedIds: const <String>[],
        recentIds: const <String>[],
      );
      // 三条 haystack 里都含「服务」，所以按分组归并后应有二段
      expect(sections.map((SettingsSearchSection s) => s.title).toList(),
          <String>['界面与显示', 'AI 接入']);
      expect(sections[0].hits.length, 2);
    });

    test('有搜索词但一个都不匹配：返回空分区列表', () {
      final List<SettingsSearchSection> sections = buildSearchSections(
        hits: <SettingsSearchHit>[hit('a')],
        query: '绝对搜不到的词',
        mostUsedIds: const <String>[],
        recentIds: const <String>[],
      );
      expect(sections, isEmpty);
    });
  });
}
