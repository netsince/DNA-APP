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

    // 内容列 720 居中 ⇒ 正文左右各留白 (1600-720)/2 = 440。
    // （字段组已经按审计 3.3 去掉卡片容器，所以量的是正文的内边距，
    //   不是某张卡片的矩形——契约是"正文收进内容列"。）
    final EdgeInsets bodyPadding =
        tester.widget<ListView>(find.byType(ListView).first).padding!
            as EdgeInsets;
    expect(
      bodyPadding.left,
      closeTo((windowWidth - AppSize.editorMaxWidth) / 2, 1.0),
    );
    expect(bodyPadding.right, bodyPadding.left);

    // 保存入口回到右下 FAB（docs/REGRESSION_AUDIT.md R4 回滚）：
    // 拇指可达，且顶栏不再放同一个动作。
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.widgetWithText(TextButton, '保存'), findsNothing);
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
    final EdgeInsets bodyPadding =
        tester.widget<ListView>(find.byType(ListView).first).padding!
            as EdgeInsets;
    expect(bodyPadding.left, closeTo(AppSpacing.lg, 1.0));
    expect(bodyPadding.right, closeTo(AppSpacing.lg, 1.0));
  });

  test('所有编辑器正文都收进内容列(防止新增编辑器漏掉)', () {
    // 拆成「表单 / 外壳」后：正文在表单，保存按钮在外壳，两边各自守。
    const List<String> bodies = <String>[
      'ta_editor/ta_editor_form',
      'world_editor/world_editor_form',
      'dialogue_style/dialogue_style_form',
      'identity_editor_page',
      'conversation_create_page',
      'group_create_page',
      'conversation_edit_page',
      'group_edit_page',
    ];
    for (final String name in bodies) {
      final String src = File('lib/pages/$name.dart').readAsStringSync();
      expect(
        src.contains('AppEditorLayout.bodyPadding'),
        isTrue,
        reason: '$name 的正文没有收进内容列(桌面宽窗口下会通栏铺开)',
      );
    }
    // 2026-11：对话范例/身份/会话/群聊等页面的「保存」已收敛到顶栏文字按钮
    // （审计 4.1：同一主操作两个入口），只有这两个页面仍是「AppBar + FAB」，
    // 因为它们的 FAB 是页面主入口之外的第二形态……仍是待收敛项，先守现状。
    const List<String> shells = <String>[
      'ta_editor_page',
      'world_editor_page',
    ];
    for (final String name in shells) {
      final String src = File('lib/pages/$name.dart').readAsStringSync();
      expect(
        src.contains('AppEditorFab'),
        isTrue,
        reason: '$name 的保存按钮没有对齐内容列',
      );
    }
  });
}
