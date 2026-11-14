import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/prompt_strategy.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat/chat_system_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// 提示词策略新增的三组（内容尺度 / 用词限制 / 排版格式）**只在新设置时才生效**。
///
/// 这是升级安全性的核心：老用户什么都不改，拼出来的提示词必须和升级前逐字一致，
/// 否则一次静默的提示词变化会让所有人的对话风格突然跑偏。
void main() {
  String buildPrompt(PromptStrategy s) =>
      ChatSystemPrompt.build(ta: null, world: null, strategy: s);

  group('默认值不改动提示词', () {
    test('默认策略不产生任何新规则', () {
      final String prompt = buildPrompt(PromptStrategy.defaults());
      expect(prompt.contains('排版要求：'), isFalse);
      expect(prompt.contains('内容尺度'), isFalse);
      expect(prompt.contains('用户偏好'), isFalse);
    });

    test('默认策略的 JSON 不落任何新键（老版本读到的是老形状）', () {
      final Map<String, dynamic> json = PromptStrategy.defaults().toJson();
      expect(json.containsKey('bannedWords'), isFalse);
      expect(json.containsKey('conflictIntensity'), isFalse);
      expect(json.containsKey('formatActionItalic'), isFalse);
      expect(json.containsKey('formatMaxParagraphs'), isFalse);
    });
  });

  group('三组设置各自生效', () {
    test('禁词写进提示词', () {
      final PromptStrategy s = PromptStrategy.defaults()
          .copyWith(bannedWords: <String>['该死', '随便']);
      final String prompt = buildPrompt(s);
      expect(prompt.contains('禁止输出词语（用户偏好）：该死、随便'), isTrue);
    });

    test('内容尺度写进提示词，未设的项不出现', () {
      final PromptStrategy s = PromptStrategy.defaults().copyWith(
        violenceIntensity: IntensityLevel.mild,
      );
      final String prompt = buildPrompt(s);
      expect(prompt.contains('内容尺度（用户接受度上限）'), isTrue);
      expect(prompt.contains('暴力描写：轻微'), isTrue);
      expect(prompt.contains('冲突与对抗'), isFalse);
    });

    test('排版格式只描述打开的那几项', () {
      final PromptStrategy s = PromptStrategy.defaults().copyWith(
        formatActionItalic: true,
      );
      final String prompt = buildPrompt(s);
      expect(prompt.contains('排版要求：'), isTrue);
      expect(prompt.contains('斜体'), isTrue);
      expect(prompt.contains('「」包裹'), isFalse);
    });

    test('段落数上限生效', () {
      final PromptStrategy s = PromptStrategy.defaults()
          .copyWith(formatMaxParagraphs: 3);
      expect(buildPrompt(s).contains('不超过 3 个段落'), isTrue);
    });
  });

  group('JSON 兼容', () {
    test('旧版 JSON（只有三个键）能解析且新字段取默认', () {
      final PromptStrategy s = PromptStrategy.fromJson(<String, dynamic>{
        'advance': 'free',
        'immersion': 'strong',
        'length': 'medium',
      });
      expect(s.advance, AdvanceStrategy.free);
      expect(s.bannedWords, isEmpty);
      expect(s.formatMaxParagraphs, 0);
      expect(s.conflictIntensity, IntensityLevel.unrestricted);
    });

    test('设置后 round-trip 不丢字段', () {
      final PromptStrategy s = PromptStrategy.defaults().copyWith(
        bannedWords: <String>['甲', '乙'],
        horrorIntensity: IntensityLevel.marked,
        formatQuoteDialogue: true,
        formatMaxParagraphs: 2,
        formatMarkdown: true,
      );
      final PromptStrategy back = PromptStrategy.fromJson(s.toJson());
      expect(back.bannedWords, <String>['甲', '乙']);
      expect(back.horrorIntensity, IntensityLevel.marked);
      expect(back.formatQuoteDialogue, isTrue);
      expect(back.formatMaxParagraphs, 2);
      expect(back.formatMarkdown, isTrue);
    });
  });

  group('三层细节项（StrategyDetails）', () {
    test('默认全部未设置：不落盘、isEmpty 为真', () {
      const StrategyDetails d = StrategyDetails();
      expect(d.isEmpty, isTrue);
      expect(d.toJson(), isEmpty);
      expect(
        PromptStrategy.defaults().toJson().containsKey('details'),
        isFalse,
      );
    });

    test('未设置的项不写进 JSON，设置过的才写', () {
      const StrategyDetails d = StrategyDetails(
        pov: Pov.third,
        pacing: Pacing.scene,
      );
      final Map<String, dynamic> json = d.toJson();
      expect(json['pov'], 'third');
      expect(json['pacing'], 'scene');
      expect(json.containsKey('reveal'), isFalse);
    });

    test('合并：角色覆盖 > 世界覆盖 > 全局，空的继承下层', () {
      const StrategyDetails global = StrategyDetails(
        pov: Pov.first,
        pacing: Pacing.scene,
        humorLevel: 2,
      );
      const StrategyDetails world = StrategyDetails(
        pacing: Pacing.fragmented,
        reveal: Reveal.layered,
      );
      const StrategyDetails ta = StrategyDetails(
        humorLevel: 5,
      );

      final StrategyDetails merged = global.mergedWith(world).mergedWith(ta);
      expect(merged.pov, Pov.first); // 只在全局设过
      expect(merged.pacing, Pacing.fragmented); // 世界覆盖全局
      expect(merged.reveal, Reveal.layered); // 只有世界设过
      expect(merged.humorLevel, 5); // 角色覆盖世界/全局
    });

    test('合并不修改原对象（不可变）', () {
      const StrategyDetails base = StrategyDetails(pov: Pov.first);
      final StrategyDetails merged = base.mergedWith(
        const StrategyDetails(pov: Pov.omniscient),
      );
      expect(base.pov, Pov.first);
      expect(merged.pov, Pov.omniscient);
    });

    test('空覆盖等价于没覆盖', () {
      const StrategyDetails base = StrategyDetails(pov: Pov.first);
      expect(base.mergedWith(const StrategyDetails()).pov, Pov.first);
      expect(base.mergedWith(null).pov, Pov.first);
    });

    test('往返序列化不丢字段', () {
      const StrategyDetails d = StrategyDetails(
        pov: Pov.omniscient,
        narrativeStructure: NarrativeStructure.threeAct,
        revealMaxPerTurn: 2,
        conflictPrimary: ConflictSource.inner,
        closureHook: true,
        catchphrases: <String>['别走', '哼'],
        sentenceLength: 3,
        motifName: '雨',
        motifEveryN: 4,
      );
      final StrategyDetails back = StrategyDetails.fromJson(d.toJson());
      expect(back.pov, Pov.omniscient);
      expect(back.narrativeStructure, NarrativeStructure.threeAct);
      expect(back.revealMaxPerTurn, 2);
      expect(back.conflictPrimary, ConflictSource.inner);
      expect(back.closureHook, isTrue);
      expect(back.catchphrases, <String>['别走', '哼']);
      expect(back.motifName, '雨');
      expect(back.motifEveryN, 4);
    });

    test('认不出的枚举名当作未设置，不抛异常', () {
      final StrategyDetails d = StrategyDetails.fromJson(<String, dynamic>{
        'pov': '来自未来的视角',
        'pacing': 42,
        'humorLevel': '3',
      });
      expect(d.pov, isNull);
      expect(d.pacing, isNull);
      expect(d.humorLevel, 3);
    });

    test('旧设置文件（没有 details）读成空', () {
      final PromptStrategy s = PromptStrategy.fromJson(<String, dynamic>{
        'advance': 'free',
        'immersion': 'strong',
        'length': 'medium',
      });
      expect(s.details.isEmpty, isTrue);
    });
  });

  group('三层细节项进提示词', () {
    TA ta(StrategyDetails? o) => TA(
      id: 't1',
      name: '甲',
      gender: '无性',
      persona: '',
      intro: '',
      opening: '',
      tags: const <String>[],
      images: const <String, String>{},
      dialogueStyle: const <DialogueTurn>[],
      strategyOverride: o,
    );

    World world(StrategyDetails? o) => World(
      id: 'w1',
      name: '世',
      summary: '',
      description: '',
      tags: const <String>[],
      forbiddenWords: const <String>[],
      entries: const <WorldEntry>[],
      strategyOverride: o,
    );

    test('全空时一条新规则都不出现（升级回归）', () {
      final String prompt = ChatSystemPrompt.build(
        ta: ta(null),
        world: world(null),
        strategy: PromptStrategy.defaults(),
      );
      for (final String marker in <String>[
        '叙事视角',
        '叙事结构',
        '场景与时序',
        '张力曲线',
        '信息揭示',
        '冲突来源',
        '收束方式',
        '环境设定',
        '配角：',
        '称呼方式',
        '情绪基调',
        '口头禅',
        '必须守住的特质',
        '口吻样本',
        '文风：',
        '意象母题',
      ]) {
        expect(prompt.contains(marker), isFalse, reason: '默认不该出现「$marker」');
      }
    });

    test('世界卡的设置会出现在提示词里', () {
      final String prompt = ChatSystemPrompt.build(
        ta: ta(null),
        world: world(
          const StrategyDetails(
            narrativeStructure: NarrativeStructure.threeAct,
            reveal: Reveal.layered,
            conflictPrimary: ConflictSource.inner,
          ),
        ),
        strategy: PromptStrategy.defaults(),
      );
      expect(prompt.contains('叙事结构：三幕'), isTrue);
      expect(prompt.contains('信息揭示：逐层揭示'), isTrue);
      expect(prompt.contains('冲突来源：内心'), isTrue);
    });

    test('角色卡覆盖世界卡，没设的项继续继承世界卡', () {
      final String prompt = ChatSystemPrompt.build(
        ta: ta(
          const StrategyDetails(
            pov: Pov.third,
            humorLevel: 5,
          ),
        ),
        world: world(
          const StrategyDetails(
            pov: Pov.first,
            narrativeStructure: NarrativeStructure.slice,
          ),
        ),
        strategy: PromptStrategy.defaults(),
      );
      expect(prompt.contains('叙事视角：第三人称'), isTrue); // 角色赢
      expect(prompt.contains('叙事视角：第一人称'), isFalse);
      expect(prompt.contains('叙事结构：切片'), isTrue); // 世界仍在
      expect(prompt.contains('幽默度 5/5'), isTrue);
    });

    test('全局默认 + 只有角色覆盖时，全局其余项保留', () {
      final PromptStrategy global = PromptStrategy.defaults().copyWith(
        details: const StrategyDetails(pov: Pov.omniscient, pacing: Pacing.scene),
      );
      final String prompt = ChatSystemPrompt.build(
        ta: ta(const StrategyDetails(humorLevel: 1)),
        world: world(null),
        strategy: global,
      );
      expect(prompt.contains('叙事视角：全知'), isTrue);
      expect(prompt.contains('场景与时序：场景推进'), isTrue);
      expect(prompt.contains('幽默度 1/5'), isTrue);
    });
  });
}
