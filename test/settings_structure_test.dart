import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 设置页重构的结构性约束(纯静态检查,不启动 UI)。
///
/// 这些断言保护「按用户任务分组、入口直达」这一设计决定,
/// 防止后续开发重新引入跳板页或把入口藏进多层导航。
void main() {
  group('设置页结构约束', () {
    late String src;

    setUpAll(() {
      src = File('lib/pages/settings_page.dart').readAsStringSync();
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
        expect(src.contains(cls), isFalse, reason: '设置主页不应再引用 $cls');
      }
    });

    test('分组数为 7(按用户任务而非技术模块)', () {
      // _Group( 共 8 处 = 7 个调用 + 1 个 `const _Group(` 构造定义。
      final int all = RegExp(r'_Group\(').allMatches(src).length;
      expect(all - 1, 7);
    });

    test('入口总数为 12', () {
      // _Entry( 共 13 处 = 12 个调用 + 1 个 `const _Entry(` 构造定义。
      final int all = RegExp(r'_Entry\(').allMatches(src).length;
      expect(all - 1, 12);
    });

    test('入口副标题强制单行(防止文案写长撑高行高)', () {
      expect(src.contains('maxLines: 1'), isTrue);
      expect(src.contains('TextOverflow.ellipsis'), isTrue);
    });

    test('保留滚动位置(从子页返回不跳回顶部)', () {
      expect(src.contains('_scrollOffset'), isTrue);
      expect(src.contains('initialScrollOffset'), isTrue);
    });

    test('每个入口都有副标题(不允许只有标题的裸入口)', () {
      // 只取真正的调用点(排除 `const _Entry(` 构造定义)。
      final Iterable<RegExpMatch> entries = RegExp(r'(?<!const )_Entry\(([\s\S]*?)\n\s*\),')
          .allMatches(src);
      expect(entries.length, 12);
      for (final RegExpMatch m in entries) {
        expect(m.group(1)!.contains('subtitle:'), isTrue,
            reason: '入口缺少副标题:\n${m.group(1)}');
      }
    });
  });
}
