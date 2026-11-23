import 'package:dna/models/prompt_strategy.dart';
import 'package:dna/models/strategy_conflicts.dart';
import 'package:dna/pages/chat/chat_system_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// 冲突检测是纯函数：每条规则一正一反，保证「该报的报、不该报的不报」。
///
/// 反例比正例重要 —— 规则写宽了会给用户一堆没用的提示，比漏报更烦人。
void main() {
  List<String> conflictsOf(StrategyDetails details, {LengthStrategy? length}) {
    final PromptStrategy s = PromptStrategy.defaults().copyWith(
      details: details,
      length: length,
    );
    return strategyConflicts(s);
  }

  test('默认策略没有任何冲突提示', () {
    expect(strategyConflicts(PromptStrategy.defaults()), isEmpty);
  });

  test('全知视角 + 逐层揭示', () {
    expect(
      conflictsOf(
        const StrategyDetails(pov: Pov.omniscient, reveal: Reveal.layered),
      ),
      isNotEmpty,
    );
    expect(
      conflictsOf(
        const StrategyDetails(pov: Pov.third, reveal: Reveal.layered),
      ),
      isEmpty,
    );
  });

  test('一次给全 + 每轮上限', () {
    expect(
      conflictsOf(
        const StrategyDetails(reveal: Reveal.all, revealMaxPerTurn: 2),
      ),
      isNotEmpty,
    );
    expect(
      conflictsOf(const StrategyDetails(reveal: Reveal.all)),
      isEmpty,
    );
  });

  test('三幕 + 跳跃剪辑', () {
    expect(
      conflictsOf(
        const StrategyDetails(
          narrativeStructure: NarrativeStructure.threeAct,
          pacing: Pacing.fragmented,
        ),
      ),
      isNotEmpty,
    );
    expect(
      conflictsOf(
        const StrategyDetails(
          narrativeStructure: NarrativeStructure.threeAct,
          pacing: Pacing.chronological,
        ),
      ),
      isEmpty,
    );
  });

  test('闭环结局 + 循环结构', () {
    expect(
      conflictsOf(
        const StrategyDetails(
          narrativeStructure: NarrativeStructure.loop,
          endingStyle: EndingStyle.closed,
        ),
      ),
      isNotEmpty,
    );
  });

  test('简短字数 + 强沉浸 + 多段要求', () {
    final PromptStrategy s = PromptStrategy.defaults().copyWith(
      length: LengthStrategy.strict,
      immersion: ImmersionStrategy.strong,
      formatMaxParagraphs: 4,
    );
    expect(strategyConflicts(s), isNotEmpty);

    final PromptStrategy ok = PromptStrategy.defaults().copyWith(
      length: LengthStrategy.strict,
      immersion: ImmersionStrategy.strong,
      formatMaxParagraphs: 1,
    );
    expect(strategyConflicts(ok), isEmpty);
  });

  test('环境描写 + 克制沉浸', () {
    expect(
      conflictsOf(const StrategyDetails(ambientEnabled: true)),
      isNotEmpty,
    );
    final PromptStrategy strong = PromptStrategy.defaults().copyWith(
      immersion: ImmersionStrategy.strong,
      details: const StrategyDetails(ambientEnabled: true),
    );
    expect(strategyConflicts(strong), isEmpty);
  });

  test('旁白斜体 + 关闭 Markdown', () {
    final PromptStrategy s =
        PromptStrategy.defaults().copyWith(formatActionItalic: true);
    expect(strategyConflicts(s), isNotEmpty);

    final PromptStrategy ok = PromptStrategy.defaults().copyWith(
      formatActionItalic: true,
      formatMarkdown: true,
    );
    expect(strategyConflicts(ok), isEmpty);
  });

  group('预览', () {
    test('默认策略的预览不含任何三层细节规则', () {
      final String text =
          ChatSystemPrompt.previewStrategy(PromptStrategy.defaults());
      expect(text.contains('叙事视角'), isFalse);
      expect(text.contains('意象母题'), isFalse);
    });

    test('设过的项会出现在预览里', () {
      final PromptStrategy s = PromptStrategy.defaults().copyWith(
        details: const StrategyDetails(
          pov: Pov.third,
          endingStyle: EndingStyle.closed,
        ),
      );
      final String text = ChatSystemPrompt.previewStrategy(s);
      expect(text.contains('叙事视角：第三人称'), isTrue);
      expect(text.contains('收束方式：闭环'), isTrue);
    });
  });
}
