import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 拖拽排序的**下标口径**。
///
/// 背景：这三个方法原先适配的是已弃用的 `ReorderableListView.onReorder` ——
/// 那个回调传的 newIndex 是"移除之前"的位置，所以方法内部要 `newIndex -= 1`。
/// 换成 `onReorderItem` 之后回调已经预先调整过，方法里再减一次就会双重调整、
/// 顺序错位（而且错得很隐蔽：只有向后拖时才错）。
///
/// 这个文件把新口径钉死：**传进来的 newIndex 就是"移除之后"的目标下标**。
TA _ta(String id, String name) => TA(
  id: id,
  name: name,
  gender: '女',
  persona: 'p',
  intro: 'i',
  opening: 'o',
  tags: const <String>[],
  images: const <String, String>{},
  dialogueStyle: const <DialogueTurn>[],
);

class _SeededHive extends HiveService {
  _SeededHive(this._tas);

  final List<TA> _tas;

  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => _tas;
  @override
  Future<List<UserIdentity>> getIdentities() async =>
      <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];

  // 写盘也走假实现：真实现会去 openBox，测试环境没有 Hive 初始化。
  @override
  Future<void> saveTas(List<TA> tas) async {}
  @override
  Future<void> saveWorlds(List<World> worlds) async {}
  @override
  Future<void> saveConversations(List<Conversation> conversations) async {}
}

void main() {
  Future<AppController> boot(List<TA> tas) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _SeededHive(tas),
    );
    await c.initialize();
    return c;
  }

  List<String> names(AppController c) =>
      c.tas.map((TA t) => t.name).toList(growable: false);

  test('reorderTas：newIndex 是"移除之后"的下标（0 → 2 移到末尾）', () async {
    final AppController c = await boot(<TA>[
      _ta('a', 'A'),
      _ta('b', 'B'),
      _ta('c', 'C'),
    ]);
    expect(names(c), <String>['A', 'B', 'C']);

    await c.reorderTas(0, 2);

    // 若方法内部又减了一次（旧口径），结果会变成 ['B','A','C']。
    expect(names(c), <String>['B', 'C', 'A'], reason: '向后拖时最容易被双重调整');
  });

  test('reorderTas：向前拖（2 → 0）', () async {
    final AppController c = await boot(<TA>[
      _ta('a', 'A'),
      _ta('b', 'B'),
      _ta('c', 'C'),
    ]);
    await c.reorderTas(2, 0);
    expect(names(c), <String>['C', 'A', 'B']);
  });

  test('reorderTas：越界下标直接忽略（不崩、不改顺序）', () async {
    final AppController c = await boot(<TA>[
      _ta('a', 'A'),
      _ta('b', 'B'),
    ]);
    await c.reorderTas(5, 0);
    await c.reorderTas(0, 5);
    expect(names(c), <String>['A', 'B']);
  });
}
