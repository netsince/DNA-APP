import 'dart:io';

import 'package:dna/models/attachment_draft.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat/ui/widgets/chat_input_bar.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天输入栏两种样式的截图（人工看用，不是断言）。
///
/// 跑法：flutter test --update-goldens test/screenshot_chat_input.dart
/// 输出：test/shots/chat_input_<样式>_<空|多行>.png
///
/// 放在 test/ 而不是 tool/：它用到了 SharedPreferences.setMockInitialValues
/// （@visibleForTesting），而 CI 跑的是**全项目** flutter analyze —— 放在 tool/
/// 会让 analyze 报 invalid_use_of_visible_for_testing_member。文件名不带 _test
/// 后缀，所以 flutter test 全量时不会收集它，需要显式指定路径才会跑。
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

void main() {
  setUpAll(() async {
    final FontLoader loader = FontLoader('SourceHanSans');
    for (final String path in <String>[
      'assets/fonts/SourceHanSansSC-Regular.otf',
      'assets/fonts/SourceHanSansSC-Medium.otf',
    ]) {
      final File file = File(path);
      if (file.existsSync()) {
        loader.addFont(
          Future<ByteData>.value(ByteData.view(file.readAsBytesSync().buffer)),
        );
      }
    }
    await loader.load();

    // 图标字体：测试环境默认不带，不加载的话按钮全是空方框，看不清布局。
    final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'G:\Tools\flutter';
    final File iconFont = File(
      '$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf',
    );
    if (iconFont.existsSync()) {
      final FontLoader icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future<ByteData>.value(ByteData.view(iconFont.readAsBytesSync().buffer)),
      );
      await icons.load();
    }
  });

  Future<void> shot(
    WidgetTester tester, {
    required String style,
    required String text,
    required String name,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat_input_style': style,
    });
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await controller.initialize();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final TextEditingController input = TextEditingController();
    addTearDown(input.dispose);
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'SourceHanSans',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A7C6F)),
        ),
        home: Scaffold(
          // 输入栏在聊天页是贴底的：这里底部对齐，才看得出它占多高。
          body: Column(
            children: <Widget>[
              const Spacer(),
              ChatInputBar(
                controller: controller,
                inputController: input,
                inputFocusNode: focus,
                attachments: AttachmentDraft(),
                visionEnabled: true,
                sending: false,
                inspirationInProgress: false,
                onSend: () {},
                onStartInspiration: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (text.isNotEmpty) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }
    // 量一下真正能打字的区域（宽 x 高）——这就是「可输入空间」的客观数字。
    final Size box = tester.getSize(find.byType(TextField));
    // ignore: avoid_print
    print('[shot] $name 输入框 ${box.width.toStringAsFixed(1)} x ${box.height.toStringAsFixed(1)}');
    final Size bar = tester.getSize(find.byType(ChatInputBar));
    // ignore: avoid_print
    print('[shot] $name 整条输入栏 ${bar.width.toStringAsFixed(1)} x ${bar.height.toStringAsFixed(1)}');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('shots/chat_input_$name.png'),
    );
  }

  testWidgets('胶囊 · 空', (WidgetTester tester) async {
    await shot(tester, style: 'capsule', text: '', name: 'capsule_empty');
  });

  testWidgets('胶囊 · 多行', (WidgetTester tester) async {
    await shot(
      tester,
      style: 'capsule',
      text: '窗外的雨还没停，\n我想再听一会儿。\n她把伞收起来，\n抖了抖上面的水。',
      name: 'capsule_text',
    );
  });

  testWidgets('经典 · 空', (WidgetTester tester) async {
    await shot(tester, style: 'classic', text: '', name: 'classic_empty');
  });

  testWidgets('经典 · 多行', (WidgetTester tester) async {
    await shot(
      tester,
      style: 'classic',
      text: '窗外的雨还没停，\n我想再听一会儿。\n她把伞收起来，\n抖了抖上面的水。',
      name: 'classic_text',
    );
  });
}
