import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 设置页重构的结构性约束（纯静态检查，不启动 UI）。
///
/// 这些断言保护「按用户任务分组、入口直达」这一设计决定，
/// 防止后续开发重新引入跳板页或把入口藏进多层导航。
///
/// 设置项的唯一数据源是 lib/pages/settings/settings_catalog.dart；
/// 设置主页负责渲染、搜索页负责查同一份数据 —— 两边都不许自带清单。
void main() {
  group('设置页结构约束', () {
    late String pageSrc;
    late String catalogSrc;
    late String searchSrc;

    setUpAll(() {
      pageSrc = File('lib/pages/settings_page.dart').readAsStringSync();
      catalogSrc =
          File('lib/pages/settings/settings_catalog.dart').readAsStringSync();
      searchSrc =
          File('lib/pages/settings/settings_search_page.dart').readAsStringSync();
    });

    test('已删除两个纯跳板页', () {
      expect(
        File('lib/pages/settings/conversation_settings_page.dart').existsSync(),
        isFalse,
        reason: 'conversation_settings_page 只列入口、不含设置项,应已删除',
      );
      expect(
        File('lib/pages/settings/appearance_settings_page.dart').existsSync(),
        isFalse,
        reason: 'appearance_settings_page 只列入口、不含设置项,应已删除',
      );
    });

    test('外观三页已合并为单页', () {
      expect(
        File('lib/pages/settings/appearance_display_page.dart').existsSync(),
        isTrue,
      );
      for (final String gone in <String>[
        'lib/pages/settings/appearance_theme_page.dart',
        'lib/pages/settings/appearance_app_page.dart',
        'lib/pages/settings/appearance_chat_page.dart',
      ]) {
        expect(File(gone).existsSync(), isFalse, reason: '$gone 应已合并');
      }
    });

    test('不再引用任何已删除的页面类', () {
      for (final String cls in <String>[
        'ConversationSettingsPage',
        'AppearanceSettingsPage',
        'AppearanceThemePage',
        'AppearanceAppPage',
        'AppearanceChatPage',
      ]) {
        expect(catalogSrc.contains(cls), isFalse, reason: '目录不应再引用 $cls');
      }
    });

    test('分组数为 8（第 7 组是社区）（按用户任务而非技术模块）', () {
      // SettingsGroup( 共 9 处 = 8 个调用 + 1 个 const 构造定义。
      final int all = RegExp(r'SettingsGroup\(').allMatches(catalogSrc).length;
      expect(all - 1, 8);
    });

    test('入口总数为 14', () {
      // SettingsEntry( 共 15 处 = 14 个调用 + 1 个 const 构造定义。
      final int all = RegExp(r'SettingsEntry\(').allMatches(catalogSrc).length;
      expect(all - 1, 14);
    });

    test('入口副标题强制单行（防止文案写长撑高行高）', () {
      expect(pageSrc.contains('maxLines: 1'), isTrue);
      expect(pageSrc.contains('TextOverflow.ellipsis'), isTrue);
    });

    test('保留滚动位置（从子页返回不跳回顶部）', () {
      expect(pageSrc.contains('_scrollOffset'), isTrue);
      expect(pageSrc.contains('initialScrollOffset'), isTrue);
    });

    test('每个入口都有副标题（不允许只有标题的裸入口）', () {
      final Iterable<RegExpMatch> entries = RegExp(
        r'(?<!const )SettingsEntry\(([\s\S]*?)\n\s*\),',
      ).allMatches(catalogSrc);
      expect(entries.length, 14);
      for (final RegExpMatch m in entries) {
        expect(
          m.group(1)!.contains('subtitle:'),
          isTrue,
          reason: '入口缺少副标题:\n${m.group(1)}',
        );
      }
    });

    test('每个入口都有搜索关键词（否则搜不到）', () {
      final Iterable<RegExpMatch> entries = RegExp(
        r'(?<!const )SettingsEntry\(([\s\S]*?)\n\s*\),',
      ).allMatches(catalogSrc);
      for (final RegExpMatch m in entries) {
        expect(
          m.group(1)!.contains('keywords:'),
          isTrue,
          reason: '入口缺少搜索关键词:\n${m.group(1)}',
        );
      }
    });

    test('设置主页与搜索页都从目录取数据，不自带清单', () {
      expect(pageSrc.contains('settingsCatalog('), isTrue,
          reason: '设置主页应按目录渲染');
      expect(searchSrc.contains('settingsCatalog('), isTrue,
          reason: '搜索页应查同一份目录，而不是另建索引');
      // 搜索页不应出现条目字面量（title: '...'），那是第二份真相的特征。
      expect(RegExp(r"title: '").hasMatch(searchSrc.replaceAll("hintText", "")),
          isFalse,
          reason: '搜索页不应内联设置项标题');
    });
  });
}
