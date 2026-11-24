import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 对话导入的落库收尾必须只有一处。
///
/// 背景：`importConversations`（ZIP 导入）与 `applyConversationImport`（带角色
/// 决议的 JSON 导入）原本各抄一遍「先自动备份 → 拆单聊/群聊 → saveConversations
/// → 造报告」和「按 id 去重后追加」，改一条去重规则要同步改两处，
/// 漏一处就是「两个导入入口行为不一致」。
///
/// 这里用源码断言钉住（不是行为测试）：一旦有人把这段再抄回去，
/// `_autoBackupZip(baseName: 'DNA_conversations'` 或 `existingIds` 的出现次数
/// 会立刻变成 2，测试失败。与 `state_views_single_source_test.dart` 同一路数。
void main() {
  final String source =
      File('lib/state/app_controller.dart').readAsStringSync();

  int countOf(String needle) =>
      needle.allMatches(source).length;

  test('对话导入的备份收尾只有一处', () {
    expect(
      countOf("baseName: 'DNA_conversations'"),
      1,
      reason: '「先备份再替换」只该在 _commitConversationImport 里写一次',
    );
  });

  test('对话导入的去重规则只有一处', () {
    // 用去重那一行本身做锚点（`existingIds` 在同一个方法里声明一次、用一次）。
    expect(
      countOf('incoming.where((Conversation c) => !existingIds.contains(c.id))'),
      1,
      reason: '「按 id 去重后追加」只该在 _commitConversationImport 里写一次',
    );
  });

  test('两个导入入口都走同一个收尾', () {
    // 1 处定义 + 2 处调用
    expect(countOf('_commitConversationImport('), 3);
  });
}
