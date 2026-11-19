import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat/chat_surface.dart';
import 'package:dna/pages/chat/chat_surface_chrome.dart';
import 'package:dna/pages/chat/ui/widgets/chat_app_bar.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [ChatSurface] 作为**通用组件**的契约。
///
/// 两个诉求：①能嵌进别的页面（不抢宿主的 Scaffold/顶栏）；
/// ②给数据就能渲染（`AppController` + 会话 id）。
class _FakeHive extends HiveService {
  _FakeHive({required this.tas, required this.conversations});

  final List<TA> tas;
  final List<Conversation> conversations;

  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => tas;
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => conversations;
  @override
  Future<void> upsertConversation(Conversation conversation) async {}
}

TA _ta(String id, String name) => TA(
  id: id,
  name: name,
  gender: '',
  persona: '',
  intro: '',
  opening: '',
  tags: <String>[],
  images: <String, String>{},
  dialogueStyle: <DialogueTurn>[],
  archived: false,
);

ConversationMessage _msg(String role, String text, int at) =>
    ConversationMessage(id: '$role-$at', role: role, text: text, timestamp: at);

Conversation _conv({
  required String id,
  required String taId,
  List<ConversationMessage> messages = const <ConversationMessage>[],
}) => Conversation(
  id: id,
  taId: taId,
  worldId: null,
  note: '',
  messages: messages,
  backgroundMode: 'color',
  summaries: <ConversationSummary>[],
  archived: false,
  isGroup: false,
  groupName: '',
  groupPrompt: '',
  memberTaIds: <String>[],
  activeTaId: taId,
  pinned: false,
);

void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(
        tas: <TA>[_ta('taA', '爱丽丝')],
        conversations: <Conversation>[
          _conv(
            id: 'c1',
            taId: 'taA',
            messages: <ConversationMessage>[_msg('user', '你好', 1)],
          ),
        ],
      ),
    );
    await c.initialize();
    return c;
  }

  testWidgets('嵌入模式：宿主自己的顶栏生效，聊天不再自带顶栏', (WidgetTester tester) async {
    final AppController c = await boot();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('宿主页')),
          body: ChatSurface(
            controller: c,
            conversationId: 'c1',
            chrome: ChatSurfaceChrome.embedded,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 宿主顶栏还在；聊天自己的 ChatAppBar 不出现（同一屏不该有两个顶栏）。
    expect(find.text('宿主页'), findsOneWidget);
    expect(find.byType(ChatAppBar), findsNothing);
    // 数据照样渲染：给 controller + 会话 id 就能出消息。
    expect(find.text('你好'), findsWidgets);
  });

  testWidgets('整页模式：自带 ChatAppBar（与 ChatPage 里一致）', (WidgetTester tester) async {
    final AppController c = await boot();
    await tester.pumpWidget(
      MaterialApp(home: ChatSurface(controller: c, conversationId: 'c1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatAppBar), findsOneWidget);
    expect(find.text('宿主页'), findsNothing);
    expect(find.text('你好'), findsWidgets);
  });

  testWidgets('同一组件可实例化两份并各自渲染（多会话并列）', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(
        tas: <TA>[_ta('taA', '爱丽丝')],
        conversations: <Conversation>[
          _conv(
            id: 'c1',
            taId: 'taA',
            messages: <ConversationMessage>[_msg('user', '第一间', 1)],
          ),
          _conv(
            id: 'c2',
            taId: 'taA',
            messages: <ConversationMessage>[_msg('user', '第二间', 2)],
          ),
        ],
      ),
    );
    await c.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('宿主页')),
          body: Column(
            children: <Widget>[
              Expanded(
                child: ChatSurface(
                  controller: c,
                  conversationId: 'c1',
                  chrome: ChatSurfaceChrome.embedded,
                ),
              ),
              Expanded(
                child: ChatSurface(
                  controller: c,
                  conversationId: 'c2',
                  chrome: ChatSurfaceChrome.embedded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatSurface), findsNWidgets(2));
    expect(find.text('第一间'), findsWidgets);
    expect(find.text('第二间'), findsWidgets);
  });
}
