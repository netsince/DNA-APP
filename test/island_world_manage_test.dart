import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/worlds_list_page.dart';
import 'package:dna/models/world.dart';

/// 「我的世界卡」的管理动作：编辑 / 下架 / 重新提审 / 撤回。
///
/// 与「我的角色卡」同一套：作者要能看出自己那本卡在哪一步，也要能改、能撤。
Map<String, dynamic> _item({
  String id = 'w1',
  String status = 'approved',
  bool hidden = false,
  String name = '幻想大陆',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'summary': '简介',
    'entry_count': 3,
    'payload_bytes': 2048,
    'copy_count': 1,
    'status': status,
    'is_hidden': hidden,
    'tags': <String>['奇幻'],
    'author': <String, dynamic>{'username': 'me', 'nickname': '我'},
    'created_at': '2026-01-02T03:04:05',
  };
}

World _world() => World(
      id: 'remote-1',
      name: '幻想大陆',
      summary: '简介',
      description: '',
      tags: const <String>['奇幻'],
      forbiddenWords: const <String>[],
      entries: const <WorldEntry>[],
    );

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> item,
  Key? key,
  Future<bool> Function(String)? hider,
  Future<void> Function(String)? resubmitter,
  Future<void> Function(String)? deleter,
  Future<String> Function(String)? sourceLoader,
  Future<void> Function(BuildContext, World, String)? editorOpener,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorldsListPage(
        // 每次重建都换 key：同类型 widget 会复用 State，initState 不再跑，
        // 列表就不会重新加载（测试里会看到上一个用例的数据）。
        key: key ?? UniqueKey(),
        title: '我的世界卡',
        manageable: true,
        loader: (int page) async => <String, dynamic>{
          'items': <Map<String, dynamic>>[item],
          'has_next': false,
        },
        hider: hider,
        resubmitter: resubmitter,
        deleter: deleter,
        sourceLoader: sourceLoader,
        editorOpener: editorOpener,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('状态徽章：待审核 / 已拒绝 / 已下架', (WidgetTester tester) async {
    await _pump(tester, item: _item(status: 'pending'));
    expect(find.text('待审核'), findsOneWidget);

    await _pump(tester, item: _item(status: 'rejected'));
    expect(find.text('已拒绝'), findsOneWidget);

    await _pump(tester, item: _item(status: 'approved', hidden: true));
    expect(find.text('已下架'), findsOneWidget);
  });

  testWidgets('下架调用 hider 并刷新', (WidgetTester tester) async {
    String? gotId;
    await _pump(
      tester,
      item: _item(),
      hider: (String id) async {
        gotId = id;
        return true;
      },
    );
    await _openMenu(tester);
    await tester.tap(find.text('下架'));
    await tester.pumpAndSettle();
    expect(gotId, 'w1');
  });

  testWidgets('已拒绝的条目给「重新提审」', (WidgetTester tester) async {
    String? gotId;
    await _pump(
      tester,
      item: _item(status: 'rejected'),
      resubmitter: (String id) async => gotId = id,
    );
    await _openMenu(tester);
    expect(find.text('重新提审'), findsOneWidget);
    await tester.tap(find.text('重新提审'));
    await tester.pumpAndSettle();
    expect(gotId, 'w1');
  });

  testWidgets('撤回要二次确认', (WidgetTester tester) async {
    String? gotId;
    await _pump(
      tester,
      item: _item(),
      deleter: (String id) async => gotId = id,
    );
    await _openMenu(tester);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    // 还没确认，不该调用
    expect(gotId, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '撤回'));
    await tester.pumpAndSettle();
    expect(gotId, 'w1');
  });

  testWidgets('编辑：取原文（不记复制）→ 打开编辑器', (WidgetTester tester) async {
    String? gotSourceId;
    World? opened;
    String? openedId;
    await _pump(
      tester,
      item: _item(),
      sourceLoader: (String id) async {
        gotSourceId = id;
        return jsonEncode(_world().toJson());
      },
      editorOpener: (BuildContext ctx, World w, String id) async {
        opened = w;
        openedId = id;
      },
    );
    await _openMenu(tester);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(gotSourceId, 'w1');
    expect(opened, isNotNull);
    expect(opened!.name, '幻想大陆');
    expect(openedId, 'w1');
  });

  testWidgets('收藏列表（非 manageable）没有管理菜单', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorldsListPage(
          title: '我收藏的世界卡',
          loader: (int page) async => <String, dynamic>{
            'items': <Map<String, dynamic>>[_item()],
            'has_next': false,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('待审核'), findsNothing);
  });
}
