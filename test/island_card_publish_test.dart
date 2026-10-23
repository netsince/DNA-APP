import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/card_publish_page.dart';
import 'package:dna/island_app/card_publish_source.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';

/// 社区「发布角色卡」：从本地角色卡里挑一张，点一下就发。
///
/// 守三件事：
/// 1. 本地 TA 映射成社区 payload（名字/标签/作者注释/seed/对话风格都要在）；
/// 2. 列表行点「发布」= 直接提交（不再进旧表单）；
/// 3. 导出 JSON 走剪贴板。
class _FakeSource implements CardPublishSource {
  _FakeSource(this.cards);

  final List<TA> cards;

  @override
  List<TA> localCards() => cards;

  @override
  Future<Uint8List?> imageBytes(String ref) async => null;
}

TA _card({String id = 'c1', String name = '幻想角色'}) => TA(
      id: id,
      name: name,
      gender: '女',
      persona: '人设',
      intro: '简介',
      opening: '开场白',
      tags: const <String>['奇幻', '治愈'],
      images: const <String, String>{},
      dialogueStyle: const <DialogueTurn>[
        DialogueTurn(user: '你好', assistant: '你好呀'),
      ],
      authorNote: '记住设定',
      authorNoteInterval: 3,
      voiceSeed: 42,
    );

void main() {
  testWidgets('点一下就发：本地角色卡映射成社区 payload', (WidgetTester tester) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPublishBody(
            source: _FakeSource(<TA>[_card()]),
            publisher: (Map<String, dynamic> payload) async {
              sent = payload;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('幻想角色'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!['name'], '幻想角色');
    expect(sent!['persona'], '人设');
    expect(sent!['tags'], <String>['奇幻', '治愈']);
    expect(sent!['author_note'], '记住设定');
    expect(sent!['author_note_interval'], 3);
    expect(sent!['seed'], '42');
    expect(
      (sent!['dialogue_style'] as List).first,
      <String, String>{'user': '你好', 'assistant': '你好呀'},
    );
    expect(find.text('已提交，等待审核'), findsOneWidget);
  });

  testWidgets('导出 JSON 复制到剪贴板', (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPublishBody(source: _FakeSource(<TA>[_card()])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导出 JSON'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied!.contains('幻想角色'), isTrue);
  });

  testWidgets('没有来源时给提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CardPublishBody())),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前环境没有可读取的本地角色卡'), findsOneWidget);
  });

  testWidgets('没有本地角色卡时给空态', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardPublishBody(source: _FakeSource(<TA>[]))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('你还没有创建过角色卡，先在「角色卡」里建一个吧'), findsOneWidget);
  });
}
