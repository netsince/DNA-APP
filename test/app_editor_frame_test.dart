import 'dart:io';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/identity_editor_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 编辑器(表单页)的桌面布局契约。
///
/// 背景:编辑器正文原来是通栏 ListView(左右各 16),1600 宽的桌面上
/// 输入框会被拉到 1500 多像素,读一行要横扫整屏,于是又空又"满"。
/// 现在正文收进 [AppSize.editorMaxWidth] 的内容列,保存按钮也对齐
/// 内容列右缘。这里锁定该行为,避免以后新增编辑器时漏掉。
class FakeHiveService extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}

void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: FakeHiveService(),
    );
    await c.initialize();
    return c;
  }

  testWidgets('宽窗口:编辑器正文收进内容列,保存按钮贴内容列右缘', (WidgetTester tester) async {
    final AppController c = await boot();
    const double windowWidth = 1600;
    tester.view.physicalSize = const Size(windowWidth, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: IdentityEditorPage(controller: c)),
    );
    await tester.pumpAndSettle();

    // 内容列 720 居中 ⇒ 左起 (1600-720)/2 = 440,卡片铺满内容列(720)。
    final Rect card = tester.getRect(find.byType(Card).first);
    expect(card.width, closeTo(AppSize.editorMaxWidth, 1.0));
    expect(card.left, closeTo((windowWidth - AppSize.editorMaxWidth) / 2, 1.0));
    // 通栏时代卡片宽度会接近整窗宽,这里明确不该发生。
    expect(card.width, lessThan(windowWidth * 0.6));

    // 保存按钮:右缘落在内容列右缘(440 + 720 = 1160),
    // 而不是窗口最右(1584)。
    final Rect fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.right, closeTo((windowWidth + AppSize.editorMaxWidth) / 2, 1.0));
  });

  testWidgets('窄窗口:编辑器铺满,外观与手机端一致', (WidgetTester tester) async {
    final AppController c = await boot();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: IdentityEditorPage(controller: c)),
    );
    await tester.pumpAndSettle();

    // 600 < 内容列 720 ⇒ 不留白,只有正文自身的 16 边距。
    final Rect card = tester.getRect(find.byType(Card).first);
    expect(card.width, closeTo(600 - 2 * AppSpacing.lg, 1.0));
    expect(card.left, closeTo(AppSpacing.lg, 1.0));
  });

  test('所有编辑器正文都收进内容列(防止新增编辑器漏掉)', () {
    const List<String> editors = <String>[
      'ta_editor_page',
      'identity_editor_page',
      'world_editor_page',
      'conversation_create_page',
      'group_create_page',
      'conversation_edit_page',
      'group_edit_page',
      'dialogue_style_page',
    ];
    for (final String name in editors) {
      final String src = File('lib/pages/$name.dart').readAsStringSync();
      expect(
        src.contains('AppEditorLayout.bodyPadding'),
        isTrue,
        reason: '$name 的正文没有收进内容列(桌面宽窗口下会通栏铺开)',
      );
      expect(
        src.contains('AppEditorFab'),
        isTrue,
        reason: '$name 的保存按钮没有对齐内容列',
      );
    }
  });
}
