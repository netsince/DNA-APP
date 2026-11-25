import 'dart:io';

import 'package:dna/models/attachment_draft.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/message_attachment.dart';
import 'package:dna/models/quick_reply.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat/ui/widgets/chat_input_bar.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHive extends HiveService {
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

/// 上传功能的 UI 截图验证（golden）。
///
/// 跑法：flutter test --update-goldens test/attachment_ui_golden_test.dart
/// 产物：test/goldens/attachment_input_*.png（用真字体渲染，能看出真实排版）。
Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('SourceHanSans');
  for (final String path in <String>[
    'assets/fonts/SourceHanSansSC-Regular.otf',
    'assets/fonts/SourceHanSansSC-Medium.otf',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future<ByteData>.value(
        ByteData.view(file.readAsBytesSync().buffer),
      ));
    }
  }
  await loader.load();

  // Material 图标字体：不加载的话 golden 里所有图标都是方框，看不出真实观感。
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final File iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      final FontLoader icons = FontLoader('MaterialIcons');
      icons.addFont(Future<ByteData>.value(
        ByteData.view(iconFont.readAsBytesSync().buffer),
      ));
      await icons.load();
    }
  }
}

MessageAttachment _fake(String name, {int size = 2048}) => MessageAttachment(
      // 引用用文件名派生：不同文件必须是不同引用（内容寻址的假设）。
      ref: '${name.hashCode.toRadixString(16).padLeft(64, '0')}.txt',
      name: name,
      mime: 'text/plain',
      size: size,
      kind: 'text',
      textChars: 100,
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required AttachmentDraft draft,
    required String style,
    bool visionEnabled = true,
    double height = 220,
  }) async {
    tester.view.physicalSize = Size(420, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await controller.initialize();
    await controller.saveChatInputStyle(style);
    final TextEditingController input =
        TextEditingController(text: '看看这个文件');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'SourceHanSans',
          colorSchemeSeed: const Color(0xFF6750A4),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              controller: controller,
              inputController: input,
              inputFocusNode: FocusNode(),
              attachments: draft,
              visionEnabled: visionEnabled,
              sending: false,
              inspirationInProgress: false,
              onSend: () {},
              onStartInspiration: () async {},
              quickReplies: const <QuickReply>[],
              onQuickReply: (_) {},
              halfScreen: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('胶囊输入栏 + 两个附件', (WidgetTester tester) async {
    final AttachmentDraft draft = AttachmentDraft()
      ..add(_fake('设定文档.md', size: 4096))
      ..add(_fake('角色表.csv', size: 15360));
    await pumpBar(tester, draft: draft, style: 'capsule');
    await expectLater(
      find.byType(ChatInputBar),
      matchesGoldenFile('goldens/attachment_input_capsule.png'),
    );
  });

  testWidgets('经典输入栏 + 两个附件', (WidgetTester tester) async {
    final AttachmentDraft draft = AttachmentDraft()
      ..add(_fake('设定文档.md', size: 4096))
      ..add(_fake('角色表.csv', size: 15360));
    await pumpBar(tester, draft: draft, style: 'classic');
    await expectLater(
      find.byType(ChatInputBar),
      matchesGoldenFile('goldens/attachment_input_classic.png'),
    );
  });

  testWidgets('点回形针弹出的上传抽屉', (WidgetTester tester) async {
    final AttachmentDraft draft = AttachmentDraft();
    await pumpBar(tester, draft: draft, style: 'capsule', height: 640);
    await tester.tap(find.byTooltip('上传文件'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/attachment_sheet.png'),
    );
  });

  testWidgets('模型不支持视觉时的抽屉（相册/照相隐藏 + 说明）', (WidgetTester tester) async {
    final AttachmentDraft draft = AttachmentDraft();
    await pumpBar(
      tester,
      draft: draft,
      style: 'capsule',
      visionEnabled: false,
      height: 640,
    );
    await tester.tap(find.byTooltip('上传文件'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/attachment_sheet_no_vision.png'),
    );
  });

  testWidgets('附件满 3 个：上传按钮禁用', (WidgetTester tester) async {
    final AttachmentDraft draft = AttachmentDraft()
      ..add(_fake('a.txt'))
      ..add(_fake('b.txt'))
      ..add(_fake('c.txt'));
    await pumpBar(tester, draft: draft, style: 'capsule');
    expect(draft.remainingSlots, 0);
    await expectLater(
      find.byType(ChatInputBar),
      matchesGoldenFile('goldens/attachment_input_full.png'),
    );
  });
}
