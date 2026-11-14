import 'package:dna/island_app/card_payload.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/prompt_strategy.dart';
import 'package:dna/models/ta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 社区发布 / 编辑的 payload 必须带上角色的「对话策略」，并且能原样读回。
///
/// 这条链路最容易断的地方是映射层：字段加了、编辑器也有了，
/// 但发布时忘了塞进 payload，社区卡就永远丢策略，而且界面上看不出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TA ta(StrategyDetails? o) => TA(
    id: 't1',
    name: '甲',
    gender: '无性',
    persona: '设定',
    intro: '',
    opening: '',
    tags: const <String>['tag'],
    images: const <String, String>{},
    dialogueStyle: const <DialogueTurn>[],
    strategyOverride: o,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('设了策略：发布 payload 里带 strategy，且是纯 JSON 形状', () {
    final Map<String, dynamic> payload = taToPublishPayload(
      ta(
        const StrategyDetails(
          pov: Pov.third,
          revealMaxPerTurn: 2,
          catchphrases: <String>['哼'],
          closureHook: true,
        ),
      ),
    );
    final Object? raw = payload['strategy'];
    expect(raw, isA<Map<String, dynamic>>());
    final Map<String, dynamic> strategy =
        (raw as Map<String, dynamic>).cast<String, dynamic>();
    expect(strategy['pov'], 'third');
    expect(strategy['revealMaxPerTurn'], 2);
    expect(strategy['catchphrases'], <String>['哼']);
    expect(strategy['closureHook'], true);
  });

  test('没设策略：payload 里不出现 strategy 键', () {
    final Map<String, dynamic> payload = taToPublishPayload(ta(null));
    expect(payload.containsKey('strategy'), isFalse);
  });

  test('空的策略对象等同于没设', () {
    final Map<String, dynamic> payload =
        taToPublishPayload(ta(const StrategyDetails()));
    expect(payload.containsKey('strategy'), isFalse);
  });

  test('从社区详情读回：strategy 会还原成角色卡的覆盖', () async {
    final TA loaded = await taFromCardDetail(<String, dynamic>{
      'name': '甲',
      'strategy': <String, dynamic>{'pov': 'first', 'humorLevel': 4},
    });
    expect(loaded.strategyOverride?.pov, Pov.first);
    expect(loaded.strategyOverride?.humorLevel, 4);
  });

  test('详情里没有 strategy：不产生覆盖', () async {
    final TA loaded = await taFromCardDetail(<String, dynamic>{'name': '甲'});
    expect(loaded.strategyOverride, isNull);
  });

  test('详情里 strategy 是脏数据：当作没设，不抛异常', () async {
    final TA loaded = await taFromCardDetail(<String, dynamic>{
      'name': '甲',
      'strategy': 'not-a-map',
    });
    expect(loaded.strategyOverride, isNull);
  });
}
