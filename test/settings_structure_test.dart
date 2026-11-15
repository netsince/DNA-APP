import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dna/pages/settings/spec/settings_spec.dart';
import 'package:dna/pages/settings/spec/settings_tree.dart';

/// 设置区的结构性约束。
///
/// 保护的是「按用户任务分组、入口直达」这个设计决定，以及**单一数据源**：
/// 设置树（spec/settings_tree.dart）同时驱动主页分组、搜索索引与字段渲染，
/// 谁也不许自带一份清单。
///
/// 断言尽量跑在**运行时数据**上（遍历 settingsTree），而不是数源码里的
/// 字符串：源码正则会被格式化和抽函数骗过去，也会在入口被引用而不是内联时
/// 数错。
void main() {
  group('设置页结构约束', () {
    late String pageSrc;
    late String catalogSrc;
    late String searchSrc;

    setUpAll(() {
      pageSrc = File('lib/pages/settings_page.dart').readAsStringSync();
      catalogSrc = File(
        'lib/pages/settings/settings_catalog.dart',
      ).readAsStringSync();
      searchSrc = File(
        'lib/pages/settings/settings_search_page.dart',
      ).readAsStringSync();
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

    test('分组数为 8，第 7 组是社区（按用户任务而非技术模块）', () {
      final Set<SettingsGroupId> groups = <SettingsGroupId>{
        for (final SettingsEntrySpec e in settingsTree) e.groupId,
      };
      expect(groups.length, 8);
      expect(settingsGroups.length, 8);
      expect(
        settingsGroups[6].id,
        SettingsGroupId.community,
        reason: '第 7 组应为社区（第 8 组是关于）',
      );
    });

    test('入口总数为 14', () {
      expect(settingsTree.length, 14);
    });

    test('入口 id 唯一（搜索与测试靠它定位）', () {
      final Set<String> ids = <String>{
        for (final SettingsEntrySpec e in settingsTree) e.id,
      };
      expect(ids.length, settingsTree.length);
    });

    test('每个入口都有副标题（不允许只有标题的裸入口）', () {
      for (final SettingsEntrySpec e in settingsTree) {
        expect(e.subtitle.trim(), isNotEmpty, reason: '入口 ${e.id} 缺少副标题');
      }
    });

    test('每个入口的 groupId 都在 settingsGroups 里（分组用 id 不用文案）', () {
      final Set<SettingsGroupId> known = <SettingsGroupId>{
        for (final SettingsGroupSpec g in settingsGroups) g.id,
      };
      for (final SettingsEntrySpec e in settingsTree) {
        expect(
          known.contains(e.groupId),
          isTrue,
          reason: '入口 ${e.id} 指向了未定义的分组 ${e.groupId}',
        );
      }
    });

    test('分组定义 id 唯一（一个分组只能定义一次）', () {
      final Set<SettingsGroupId> ids = <SettingsGroupId>{
        for (final SettingsGroupSpec g in settingsGroups) g.id,
      };
      expect(ids.length, settingsGroups.length);
    });

    test('入口副标题强制单行（防止文案写长撑高行高）', () {
      expect(pageSrc.contains('maxLines: 1'), isTrue);
      expect(pageSrc.contains('TextOverflow.ellipsis'), isTrue);
    });

    test('保留滚动位置（从子页返回不跳回顶部）', () {
      expect(pageSrc.contains('_scrollOffset'), isTrue);
      expect(pageSrc.contains('initialScrollOffset'), isTrue);
    });

    test('搜索覆盖「不在主页但声明驱动」的页面', () {
      // 采样参数/自由剪图/检查更新不在设置主页，但用户搜「温度」应该找得到。
      expect(
        searchSrc.contains('settingsDetachedEntries'),
        isTrue,
        reason: '搜索索引必须把脱离主页的声明页也算进去',
      );
    });

    test('设置主页与搜索页都从同一棵树取数据，不自带清单', () {
      expect(
        pageSrc.contains('settingsCatalog('),
        isTrue,
        reason: '设置主页应按目录渲染',
      );
      expect(
        searchSrc.contains('buildSettingsSearchIndex('),
        isTrue,
        reason: '搜索页应从设置树建索引，而不是另建一份清单',
      );
      expect(
        catalogSrc.contains('settingsTree'),
        isTrue,
        reason: '目录（适配层）必须从设置树取数据',
      );
    });

    test('搜索页不内联任何入口标题（那是第二份真相）', () {
      // 只看代码行：注释里提到入口名是正常的（那是解释，不是数据）。
      final String codeOnly = searchSrc
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final SettingsEntrySpec e in settingsTree) {
        expect(
          codeOnly.contains(e.title),
          isFalse,
          reason: '搜索页的代码里内联了入口标题「${e.title}」',
        );
      }
    });
  });
}
