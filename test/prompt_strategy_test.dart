import 'package:dna/models/prompt_strategy.dart';
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
}
