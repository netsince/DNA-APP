import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/pages/my_home_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「我家」瀑布流与排序模式的契约。
///
/// * 卡片高度由立绘槽位决定(1:1 → 竖 → 横):不用等图片解码就知道该给
///   多高,所以排版不会跳;
/// * 点卡片进展示页;长按进入排序模式(网格切成可拖拽列表),点「完成」退出;
/// * 归档列表不参与排序。
class _FakeHive extends HiveService {
  _FakeHive(this.tas);

  final List<TA> tas;

  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => tas;
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
  @override
  Future<void> upsertTa(TA ta) async {}
  @override
  Future<void> saveTas(List<TA> tas) async {}
}

TA _ta(
  String id,
  String name, {
  Map<String, String> images = const <String, String>{},
  bool archived = false,
}) => TA(
  id: id,
  name: name,
  gender: '',
  persona: '',
  intro: '来自北境的旅人。',
  opening: '',
  tags: const <String>[],
  images: images,
  dialogueStyle: const <DialogueTurn>[],
  archived: archived,
);

/// FitText 是 Text 子类且内部再包一层 Text,只匹配内层真实 Text。
Finder label(String s) => find.byWidgetPredicate(
  (Widget w) => w is Text && w.data == s && w is! FitText,
);

void main() {
  Future<AppController> boot(List<TA> tas) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(tas),
    );
    await c.initialize();
    return c;
  }

  Future<void> pumpBody(
    WidgetTester tester,
    AppController c, {
    Size size = const Size(600, 1000),
    bool archived = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaListBody(
            controller: c,
            showArchived: archived,
            onCreateTa: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('瀑布流:窄窗口排两列,卡片高度按立绘槽位比例', (WidgetTester tester) async {
    final AppController c = await boot(<TA>[
      _ta('taA', '爱丽丝'),
      _ta('taB', '鲍勃'),
      // 只有竖版立绘 ⇒ 卡片应是 9:16 的高卡(图片文件不存在也不影响比例)
      _ta('taC', '卡罗尔', images: <String, String>{'portrait': 'p.png'}),
      _ta('taD', '戴维'),
    ]);
    await pumpBody(tester, c);

    // 前两张卡同处第一行(说明是两列而不是单列)
    final Rect first = tester.getRect(label('爱丽丝'));
    final Rect second = tester.getRect(label('鲍勃'));
    expect(first.top, closeTo(second.top, 1.0));
    expect(first.left, isNot(closeTo(second.left, 1.0)));

    // 竖版立绘的卡片按 9:16 定高
    final Iterable<AspectRatio> ratios = tester.widgetList<AspectRatio>(
      find.byType(AspectRatio),
    );
    expect(
      ratios.any((AspectRatio a) => (a.aspectRatio - 9 / 16).abs() < 0.001),
      isTrue,
      reason: '只有竖版立绘的角色应得到 9:16 的卡片',
    );
  });

  testWidgets('宽窗口列数更多', (WidgetTester tester) async {
    final AppController c = await boot(<TA>[
      _ta('taA', '爱丽丝'),
      _ta('taB', '鲍勃'),
      _ta('taC', '卡罗尔'),
      _ta('taD', '戴维'),
    ]);
    await pumpBody(tester, c, size: const Size(1400, 1000));

    // 四列:四张卡的第一行在同一水平线上
    final double top = tester.getRect(label('爱丽丝')).top;
    expect(tester.getRect(label('鲍勃')).top, closeTo(top, 1.0));
    expect(tester.getRect(label('卡罗尔')).top, closeTo(top, 1.0));
    expect(tester.getRect(label('戴维')).top, closeTo(top, 1.0));
  });

  testWidgets('长按进入排序模式,点「完成」退出', (WidgetTester tester) async {
    final AppController c = await boot(<TA>[
      _ta('taA', '爱丽丝'),
      _ta('taB', '鲍勃'),
    ]);
    await pumpBody(tester, c);
    expect(find.byType(ReorderableListView), findsNothing);

    await tester.longPress(label('爱丽丝'));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(label('完成'), findsOneWidget);
    expect(find.textContaining('拖动调整顺序'), findsWidgets);

    await tester.tap(label('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsNothing);
    // 退出后回到卡片墙
    expect(label('爱丽丝'), findsOneWidget);
  });

  testWidgets('排序模式里拖动真的改变顺序', (WidgetTester tester) async {
    final AppController c = await boot(<TA>[
      _ta('taA', '爱丽丝'),
      _ta('taB', '鲍勃'),
      _ta('taC', '卡罗尔'),
    ]);
    await pumpBody(tester, c);
    await tester.longPress(label('爱丽丝'));
    await tester.pumpAndSettle();

    final List<String> before = c.tas.map((TA t) => t.id).toList();
    expect(before.first, 'taA');

    await tester.drag(find.byIcon(Icons.drag_handle).first, const Offset(0, 130));
    await tester.pumpAndSettle();

    final List<String> after = c.tas.map((TA t) => t.id).toList();
    expect(after, isNot(equals(before)), reason: '拖动后顺序应变化');
  });

  testWidgets('归档列表不参与排序(长按无效)', (WidgetTester tester) async {
    final AppController c = await boot(<TA>[
      _ta('taA', '爱丽丝', archived: true),
      _ta('taB', '鲍勃', archived: true),
    ]);
    await pumpBody(tester, c, archived: true);

    await tester.longPress(label('爱丽丝'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsNothing);
    expect(label('完成'), findsNothing);
  });
}
