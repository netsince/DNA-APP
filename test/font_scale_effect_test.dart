import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/pages/settings/appearance_display_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/font_scale.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

///字号档位「真的生效」的行为验证。
///
///这是上一轮漏掉的那类测试：`font_scale_smoke_test`只断言"不溢出"，
///所以聊天正文固定14px、字号设置完全到不了它的时候，测试照样是绿的。
///这里换成**量尺寸**：同一段文字在两个档位下渲染，高度必须变大。
const String kMarker = '打点计数七个字';

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

TA _ta() => TA(
 id: 'ta-1',
 name: '角色甲',
 gender: '',
 persona: '',
 intro: '',
 opening: '',
 tags: <String>[],
 images: const <String, String>{},
 dialogueStyle: const <DialogueTurn>[],
);

Conversation _conv(String text) => Conversation(
 id: 'c1',
 taId: 'ta-1',
 worldId: null,
 note: '',
 messages: <ConversationMessage>[
 ConversationMessage(id: 'm1', role: 'assistant', text: text, timestamp:1),
 ],
 backgroundMode: 'none',
 summaries: const <ConversationSummary>[],
 archived: false,
 isGroup: false,
 groupName: '',
 groupPrompt: '',
 memberTaIds: <String>['ta-1'],
 activeTaId: 'ta-1',
);

void main() {
 Future<AppController> boot() async {
 SharedPreferences.setMockInitialValues(<String, Object>{});
 final AppController c = AppController(
 settingsService: SettingsService(),
 openAiService: OpenAiService(),
 taService: TaService(),
 hiveService: _FakeHive(
 tas: <TA>[_ta()],
 //足够长，保证一定换行：字号变大时行高与行数都会增长。
 conversations: <Conversation>[
 _conv('$kMarker，我们把这段话写长一点点，好让它在这个宽度下必须换行，'
 '这样行高与总高度都能反映字号变化。再看一遍：$kMarker。'),
 ],
 ),
 );
 await c.initialize();
 return c;
 }

 ///用指定档位包一层 MediaQuery（模拟全局注入后的效果）。
 Widget wrap(int step, Widget child) {
 final double scale = AppFontScale.scaleOf(step) ??1.0;
 return MediaQuery(
 data: MediaQueryData(textScaler: TextScaler.linear(scale)),
 child: child,
 );
 }

 Future<void> settle(WidgetTester tester) async {
 for (int i =0; i <10; i++) {
 await tester.pump(const Duration(milliseconds:60));
 }
 }

 testWidgets('聊天正文会跟着字号变大（曾经完全不动）', (WidgetTester tester) async {
 tester.view.physicalSize = const Size(390,844);
 tester.view.devicePixelRatio =1.0;
 addTearDown(tester.view.reset);
 final AppController c = await boot();

 Future<double> bodyHeight(int step) async {
 await tester.pumpWidget(
 wrap(step, MaterialApp(home: ChatPage(controller: c, conversationId: 'c1'))),
 );
 await settle(tester);
 final Finder body = find.byWidgetPredicate(
 (Widget w) =>
 w is Text &&
 w is! FitText &&
 w.textSpan != null &&
 w.textSpan!.toPlainText().contains(kMarker),
 );
 expect(body, findsWidgets, reason: '没找到消息正文');
 return tester.getSize(body.first).height;
 }

 final double normal = await bodyHeight(2); //1.0
 final double huge = await bodyHeight(5); //1.45
 expect(normal, greaterThan(0));
 expect(
 huge,
 greaterThan(normal *1.3),
 reason: '正文高度应随字号明显增长（旧实现里这里完全相等）',
 );
 });

 testWidgets('设置页里的正文行高随字号增长（按行量，不按整页求和）', (WidgetTester tester) async {
 //视口开高一点：设置页是 ListView（懒构建），窗口太矮时那一段可能压根没建出来。
 tester.view.physicalSize = const Size(390,2000);
 tester.view.devicePixelRatio =1.0;
 addTearDown(tester.view.reset);
 final AppController c = await boot();

 //注意：**不能**把整页的 RenderParagraph高度求和来比较 ——
 // ListView是懒构建的，字变大后同一视口里能建出来的条目更少，
 //求和反而会变小（我第一次就是这么写的，指标本身就是错的）。
 Future<double> lineHeight(int step) async {
 await tester.pumpWidget(
 wrap(step, MaterialApp(home: AppearanceDisplayPage(controller: c))),
 );
 await tester.pump();
 final Finder line = find.byWidgetPredicate(
 (Widget w) =>
 w is Text &&
 w.data != null &&
 w.data!.startsWith('聊天只占下半屏'),
 );
 expect(line, findsWidgets, reason: '没找到取样行');
 return tester.getSize(line.first).height;
 }

 final double normal = await lineHeight(2);
 final double huge = await lineHeight(5);
 expect(normal, greaterThan(0));
 expect(huge, greaterThan(normal), reason: '同一行文字在超大档下必须更高');
 });
}
