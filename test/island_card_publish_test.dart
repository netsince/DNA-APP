import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/auth_session.dart';
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
    // 发布需要登录态；测试里直接注入，不走网络。
    AuthSession.instance.debugSetSession(
      token: 'test-token',
      user: <String, dynamic>{'username': 'tester'},
    );
    addTearDown(() => AuthSession.instance.debugSetSession());
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

  test('编辑器保存按钮必须用调用方给的文案', () {
    // 曾经写死成「保存TA」：社区里明明走的是「发布」，按钮却写着保存，
    // 而且 saveLabel 参数只声明没接线 —— 两边都对不上。
    final String src =
        File('lib/pages/ta_editor_page.dart').readAsStringSync();
    expect(src.contains('label: FitText(widget.saveLabel)'), isTrue,
        reason: 'FAB 文案必须来自 widget.saveLabel');
    expect(src.contains('tooltip: widget.saveLabel'), isTrue,
        reason: '顶栏保存按钮的 tooltip 也要跟着走');
    expect(src.contains("'保存TA'"), isFalse,
        reason: '不要再写死文案');
  });

  test('保存失败必须把原因显示出来，而不是静默吞掉', () {
    // 以前 _save 没有 try/catch：发布失败时异常只进控制台，
    // 用户看到的就是「点了没反应」。
    final String src =
        File('lib/pages/ta_editor_page.dart').readAsStringSync();
    final int start = src.indexOf('Future<void> _save() async {');
    expect(start, greaterThan(-1));
    final String body = src.substring(start, start + 1600);
    expect(body.contains('try {'), isTrue, reason: '_save 必须捕获异常');
    expect(body.contains('_errorText(e)'), isTrue, reason: '失败原因要弹给用户看');
    expect(body.contains('SnackBar('), isTrue, reason: '原因要通过 SnackBar 展示');
  });

  testWidgets('未登录时点发布会被拦住', (WidgetTester tester) async {
    AuthSession.instance.debugSetSession();
    addTearDown(() => AuthSession.instance.debugSetSession());
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
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();
    expect(sent, isNull, reason: '未登录不该真的发出去');
    expect(find.text('请先登录后再发布'), findsOneWidget);
  });

  testWidgets('新建：编辑器按钮写「发布到社区」，点它真的发布',
      (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 'test-token',
      user: <String, dynamic>{'username': 'tester'},
    );
    addTearDown(() => AuthSession.instance.debugSetSession());
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPublishBody(
            source: _FakeSource(<TA>[]),
            publisher: (Map<String, dynamic> payload) async {
              sent = payload;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 编辑器内容较长，放大视口让名字输入框也被构建出来。
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('新建角色卡并发布'));
    await tester.pumpAndSettle();
    // 名称必填（社区侧前置校验），先填一个名字再发布。
    final Finder nameField = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.labelText == '名字 *',
    );
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, '新角色');
    await tester.pumpAndSettle();
    // 编辑器里必须叫「发布到社区」，不是「保存TA / 保存」。
    // 注意 FitText 会渲染测量副本，同一段文字可能匹配到多个 Text。
    expect(find.text('发布到社区'), findsWidgets);
    expect(find.text('保存TA'), findsNothing);
    final Finder fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget, reason: '编辑器的保存按钮是右下角 FAB');
    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(sent, isNotNull, reason: '点保存按钮必须真的走发布');
  });

  testWidgets('空名字的卡不能发到社区', (WidgetTester tester) async {
    AuthSession.instance.debugSetSession(
      token: 'test-token',
      user: <String, dynamic>{'username': 'tester'},
    );
    addTearDown(() => AuthSession.instance.debugSetSession());
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPublishBody(
            source: _FakeSource(<TA>[_card(name: '')]),
            publisher: (Map<String, dynamic> payload) async {
              sent = payload;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();
    expect(sent, isNull, reason: '空名字不该发出去');
    expect(find.text('请填写角色卡名称'), findsOneWidget);
  });

  test('名称必填只在社区发布侧，不能污染共享编辑器', () {
    // 本地角色卡允许叫空名，社区规则只该管「发到社区」这条路径。
    final String editor =
        File('lib/pages/ta_editor_page.dart').readAsStringSync();
    expect(editor.contains('请填写角色卡名称'), isFalse,
        reason: '共享编辑器不该有社区的名字校验');
    final String publish =
        File('lib/island_app/card_publish_page.dart').readAsStringSync();
    expect(publish.contains('请填写角色卡名称'), isTrue);
  });
}
