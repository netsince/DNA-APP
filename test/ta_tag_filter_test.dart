import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/my_home/ta_tag_filter.dart';
import 'package:dna/pages/my_home/tag_filter_bar.dart';
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

/// 「我家」标签筛选的契约。
///
/// 标签早就存在 TA 模型里、编辑器里也早能填，此前没有任何地方消费它。
/// 这条筛选条是唯一的消费入口，所以规则都压成纯函数在这里穷举。
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

TA _ta(String id, String name, {List<String> tags = const <String>[]}) => TA(
  id: id,
  name: name,
  gender: '',
  persona: '',
  intro: '',
  opening: '',
  tags: tags,
  images: const <String, String>{},
  dialogueStyle: const [],
);

/// FitText 内部还包一层 Text，这里只匹配内层真实 Text（与瀑布流测试同款）。
Finder label(String s) => find.byWidgetPredicate(
  (Widget w) => w is Text && w.data == s && w is! FitText,
);

/// 按标签文字定位筛选 chip。
///
/// 不能用 widgetWithText(ChoiceChip, ...)：FitText 既是 Text 子类、内部又包
/// 一层 Text，同一个 chip 会被找到两次（祖先匹配重复）。
Finder chip(String tag) => find.byWidgetPredicate(
  (Widget w) =>
      w is ChoiceChip &&
      w.label is FitText &&
      (w.label as FitText).data == tag,
);

void main() {
  group('标签规整 normalizeTagList', () {
    test('去空白、丢空串、丢哨兵值', () {
      expect(
        normalizeTagList(<String>[' 古风 ', '', '  ', '现代', kUntaggedSelection]),
        <String>['古风', '现代'],
      );
    });
  });

  group('收集标签 collectTags', () {
    test('按出现次数降序', () {
      final List<String> tags = collectTags(<TA>[
        _ta('1', 'A', tags: <String>['现代', '古风']),
        _ta('2', 'B', tags: <String>['古风']),
        _ta('3', 'C', tags: <String>['古风', '现代']),
      ]);
      expect(tags.first, '古风', reason: '古风出现 3 次，最多');
      expect(tags, <String>['古风', '现代']);
    });

    test('次数相同时按「首次出现」的先后，结果稳定不跳变', () {
      final List<String> tags = collectTags(<TA>[
        _ta('1', 'A', tags: <String>['武侠', '古风']),
        _ta('2', 'B', tags: <String>['现代']),
      ]);
      expect(tags, <String>['武侠', '古风', '现代']);
    });

    test('同一 TA 内的重复标签只算一次；空标签不计入', () {
      final List<String> tags = collectTags(<TA>[
        _ta('1', 'A', tags: <String>['古风', '古风', '  ', '']),
      ]);
      expect(tags, <String>['古风']);
    });

    test('没有任何标签时返回空', () {
      expect(collectTags(<TA>[_ta('1', 'A')]), isEmpty);
    });
  });

  group('未分类判定 hasUntagged', () {
    test('有裸 TA 就为真', () {
      expect(hasUntagged(<TA>[_ta('1', 'A', tags: <String>['古风']), _ta('2', 'B')]), isTrue);
    });
    test('全都打了标签就为假', () {
      expect(hasUntagged(<TA>[_ta('1', 'A', tags: <String>['古风'])]), isFalse);
    });
  });

  group('过滤 filterTasByTag', () {
    final List<TA> tas = <TA>[
      _ta('1', '古风A', tags: <String>['古风', '武侠']),
      _ta('2', '现代B', tags: <String>['现代']),
      _ta('3', '无名C'),
    ];

    test('选择为 null 时原样返回（含顺序）', () {
      expect(filterTasByTag(tas, null).map((TA t) => t.id).toList(), <String>['1', '2', '3']);
    });

    test('按标签过滤，未命中的不出现', () {
      expect(filterTasByTag(tas, '古风').map((TA t) => t.id).toList(), <String>['1']);
      expect(filterTasByTag(tas, '现代').map((TA t) => t.id).toList(), <String>['2']);
    });

    test('「未分类」只给没有任何标签的 TA', () {
      expect(
        filterTasByTag(tas, kUntaggedSelection).map((TA t) => t.id).toList(),
        <String>['3'],
      );
    });
  });

  group('失效选择回落 effectiveTagSelection', () {
    test('标签还在 ⇒ 保留', () {
      expect(
        effectiveTagSelection('古风', <String>['古风'], untaggedPresent: false),
        '古风',
      );
    });

    test('标签没了（被改标签/被归档）⇒ 回落全部', () {
      expect(
        effectiveTagSelection('古风', <String>['现代'], untaggedPresent: false),
        isNull,
      );
    });

    test('未分类选区在没有裸 TA 时也回落', () {
      expect(
        effectiveTagSelection(kUntaggedSelection, <String>['古风'], untaggedPresent: false),
        isNull,
      );
      expect(
        effectiveTagSelection(kUntaggedSelection, <String>['古风'], untaggedPresent: true),
        kUntaggedSelection,
      );
    });

    test('null 永远是 null', () {
      expect(effectiveTagSelection(null, <String>['古风'], untaggedPresent: true), isNull);
    });
  });

  group('筛选条交互', () {
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

    Future<void> pumpBody(WidgetTester tester, AppController c) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaListBody(
              controller: c,
              showArchived: false,
              selectedTag: ValueNotifier<String?>(null),
              onCreateTa: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final List<TA> tas = <TA>[
      _ta('1', '古风A', tags: <String>['古风', '武侠']),
      _ta('2', '现代B', tags: <String>['现代']),
      _ta('3', '无名C'),
    ];

    testWidgets('有标签：顶部出现筛选条，分类与未分类都在', (WidgetTester tester) async {
      final AppController c = await boot(tas);
      await pumpBody(tester, c);

      expect(find.byType(TagFilterBar), findsOneWidget);
      expect(chip('全部'), findsOneWidget);
      expect(chip('古风'), findsOneWidget);
      expect(chip('武侠'), findsOneWidget);
      expect(chip('现代'), findsOneWidget);
      expect(chip('未分类'), findsOneWidget);
    });

    testWidgets('点标签只留该标签的角色，再点一次回到全部', (WidgetTester tester) async {
      final AppController c = await boot(tas);
      await pumpBody(tester, c);
      expect(label('古风A'), findsOneWidget);
      expect(label('现代B'), findsOneWidget);

      await tester.tap(chip('古风'));
      await tester.pumpAndSettle();
      expect(label('古风A'), findsOneWidget);
      expect(label('现代B'), findsNothing);
      expect(label('无名C'), findsNothing);

      await tester.tap(chip('古风'));
      await tester.pumpAndSettle();
      expect(label('现代B'), findsOneWidget, reason: '再点一次应取消筛选');
      expect(label('无名C'), findsOneWidget);
    });

    testWidgets('「未分类」只留没有标签的角色', (WidgetTester tester) async {
      final AppController c = await boot(tas);
      await pumpBody(tester, c);

      await tester.tap(chip('未分类'));
      await tester.pumpAndSettle();
      expect(label('无名C'), findsOneWidget);
      expect(label('古风A'), findsNothing);
      expect(label('现代B'), findsNothing);
    });

    testWidgets('一个标签都没有：不渲染筛选条（页面保持原样）', (WidgetTester tester) async {
      // 用多字名：单字名会和卡片左上角的头像首字撞车，label 会数到两次。
      final AppController c = await boot(<TA>[
        _ta('1', '角色甲'),
        _ta('2', '角色乙'),
      ]);
      await pumpBody(tester, c);
      expect(find.byType(TagFilterBar), findsNothing);
      expect(label('角色甲'), findsOneWidget);
    });
  });
}
