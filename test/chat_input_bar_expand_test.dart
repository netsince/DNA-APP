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
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat_input_style': 'capsule',
    });
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

  Future<void> pumpBar(WidgetTester tester) async {
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

  testWidgets('空且未聚焦：紧凑（输入框只占约半屏）', (WidgetTester tester) async {
    await pumpBar(tester);
    expect(fieldWidth(tester), lessThan(260),
        reason: '没事的时候不该占满整行');
  });

  testWidgets('聚焦即展开：输入框变宽（按钮挪到下一行）', (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300),
        reason: '点进来准备打字时，宽度要让出来');
  });

  testWidgets('有文字时保持展开（哪怕焦点丢了）', (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(TextField), '窗外的雨还没停。');
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300));

    focus.unfocus();
    await tester.pumpAndSettle();
    expect(fieldWidth(tester), greaterThan(300),
        reason: '有内容就不能缩回去，否则文字会被挤在一半宽里');
  });

  testWidgets('发送后清空但键盘还在：不缩回', (WidgetTester tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.pumpAndSettle();
    // 模拟发送后清空（焦点仍在输入框上）。
    input.clear();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue, reason: '这个用例要覆盖「焦点仍在」的情形');
    expect(fieldWidth(tester), greaterThan(300),
        reason: '刚发完就缩回去会让下一次输入再弹一次，很难受');
  });
}
