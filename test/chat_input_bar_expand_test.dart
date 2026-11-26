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
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 输入栏的「按需展开」：空着且没聚焦时紧凑，一旦要输入就让出宽度。
///
/// 锁的是行为而不是具体像素：输入框的宽度必须真的变大（按钮从同一行挪到下一行）。
/// 两种样式（胶囊 / 经典）的布局是两个独立分支，各有一组用例。
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
  late AppController controller;
  late TextEditingController input;
  late FocusNode focus;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    input = TextEditingController();
    focus = FocusNode();
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
  });

  Future<void> pumpBar(WidgetTester tester, {String style = 'capsule'}) async {
    await controller.initialize();
    await controller.patchSettings('chatInputStyle', style);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
  }

  double fieldWidth(WidgetTester tester) =>
      tester.getSize(find.byType(TextField)).width;

  testWidgets('胶囊 · 空且未聚焦：紧凑（输入框只占约半屏）', (WidgetTester tester) async {
    await pumpBar(tester);
    expect(fieldWidth(tester), lessThan(260),
        reason: '没事的时候不该占满整行');
  });

  testWidgets('胶囊 · 聚焦即展开：输入框变宽（按钮挪到下一行）',
      (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300),
        reason: '点进来准备打字时，宽度要让出来');
  });

  testWidgets('胶囊 · 有文字时保持展开（哪怕焦点丢了）', (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(TextField), '窗外的雨还没停。');
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300));

    focus.unfocus();
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300),
        reason: '有内容就不能缩回去，否则文字会被挤在一半宽里');
  });

  testWidgets('胶囊 · 发送后清空但键盘还在：不缩回', (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.pumpAndSettle();
    input.clear();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue, reason: '这个用例要覆盖「焦点仍在」的情形');
    expect(fieldWidth(tester), greaterThan(300),
        reason: '刚发完就缩回去会让下一次输入再弹一次，很难受');
  });

  testWidgets('经典 · 空且未聚焦：紧凑', (WidgetTester tester) async {
    await pumpBar(tester, style: 'classic');
    expect(fieldWidth(tester), lessThan(260));
  });

  testWidgets('经典 · 聚焦即展开，且比胶囊更宽（没有外层容器内边距）',
      (WidgetTester tester) async {
    await pumpBar(tester, style: 'classic');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(340),
        reason: '经典样式没有胶囊外壳，展开后应该更贴近满屏');
  });

  testWidgets('经典 · 有文字时保持展开', (WidgetTester tester) async {
    await pumpBar(tester, style: 'classic');
    await tester.enterText(find.byType(TextField), '窗外的雨还没停。');
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(340));
  });
}
