import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late bool sending;
  late int sendCalls;

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
    sending = false;
    sendCalls = 0;
  });

  Future<void> pumpBar(WidgetTester tester, {VoidCallback? onStop}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: controller,
          inputController: input,
          inputFocusNode: focus,
          sending: sending,
          inspirationInProgress: false,
          onSend: () => sendCalls++,
          onStartInspiration: () async {},
          onStopGeneration: onStop,
        ),
      ),
    ));
  }

  Finder sendArrow() => find.byIcon(Icons.arrow_upward_rounded);
  Finder stopButton() => find.byIcon(Icons.stop_rounded);

  testWidgets('生成中、输入框为空时也显示「停止生成」按钮(回归 Bug①)',
      (WidgetTester tester) async {
    sending = true;
    input.text = ''; // 发送即清空输入:此刻没有字
    await pumpBar(tester, onStop: () {});

    expect(stopButton(), findsOneWidget);
    // 生成中不出现发送箭头,也不会误显灵感按钮。
    expect(sendArrow(), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
  });

  testWidgets('空闲空输入:无停止、无发送箭头,显示灵感按钮', (WidgetTester tester) async {
    sending = false;
    input.text = '';
    await pumpBar(tester);

    expect(stopButton(), findsNothing);
    expect(sendArrow(), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
  });

  testWidgets('停止后同一手势误触到重建的发送键时不误发(回归 Bug②)',
      (WidgetTester tester) async {
    sending = true;
    await pumpBar(tester, onStop: () {});

    // 生成期间输入框填入残留文字:_hasInput 随之变 true,按钮区仍显示停止。
    input.text = '残留文字';
    await tester.pump();
    expect(stopButton(), findsOneWidget);

    // 点停止:服务端把 _sending 翻为 false,触发按钮重建为发送键。
    await tester.tap(stopButton());
    sending = false;
    await pumpBar(tester, onStop: () {}); // 以新 sending 重建
    await tester.pump();
    expect(sendArrow(), findsOneWidget);

    // 同一手势的抬手落在重建后的发送键上:必须被冷却吞掉,不得误发。
    await tester.tap(sendArrow());
    await tester.pump();
    expect(sendCalls, 0, reason: '停止后同一手势的误触不应触发发送');

    // 冷却(350ms)过后再点,才允许正常发送。
    // 注意:冷却用墙钟 DateTime.now(),故须以真实异步等待推进(tester.runAsync),
    // 单纯 tester.pump(duration) 只推快假时钟、不会让墙钟前进。
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.tap(sendArrow());
    await tester.pump();
    expect(sendCalls, 1, reason: '冷却过后应允许重新发送');
  });
}
