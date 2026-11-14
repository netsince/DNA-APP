import 'prompt_strategy.dart';

/// 策略冲突检测：把「互相打架」的组合翻译成一句人话。
///
/// 纯函数、不依赖 Flutter，因此可以直接单测；设置页的高级分页、角色卡与世界卡
/// 的编辑页共用同一份规则与文案，避免三处各写一套说法。
///
/// 只提示、不阻止：用户可能就是要那个效果，我们只负责把后果说清楚。
List<String> strategyConflicts(PromptStrategy strategy) {
  final List<String> out = <String>[];
  final StrategyDetails d = strategy.details;

  // 1) 视角与揭示方式
  if (d.pov == Pov.omniscient && d.reveal == Reveal.layered) {
    out.add('视角选了「全知」，叙述者本来就知道一切，「逐层揭示」很难成立。');
  }

  // 2) 一次给全 + 每轮上限
  if (d.reveal == Reveal.all &&
      d.revealMaxPerTurn != null &&
      d.revealMaxPerTurn! > 0) {
    out.add('「一次给全」时「每轮最多揭示几条」不会生效。');
  }

  // 3) 三幕结构 + 跳跃剪辑
  if (d.narrativeStructure == NarrativeStructure.threeAct &&
      d.pacing == Pacing.fragmented) {
    out.add('「三幕」需要连续的推进感，和「跳跃剪辑」不太好配合。');
  }

  // 4) 结构 + 单场景
  if (d.narrativeStructure == NarrativeStructure.slice &&
      d.endingStyle == EndingStyle.loop) {
    out.add('「切片（单场景）」通常收在一个瞬间，和「回环」结局容易别扭。');
  }

  // 5) 闭环结局 + 循环结构
  if (d.endingStyle == EndingStyle.closed &&
      d.narrativeStructure == NarrativeStructure.loop) {
    out.add('叙事结构是「循环」，结局又要「闭环」，两者对不上。');
  }

  // 6) 字数 / 沉浸 / 段落数 三者打架
  if (strategy.length == LengthStrategy.strict &&
      strategy.immersion == ImmersionStrategy.strong &&
      strategy.formatMaxParagraphs > 2) {
    out.add('字数选了「简短」、沉浸选了「强」，又要求 3 段以上，三条互相限制。');
  }

  // 7) 环境描写 + 克制沉浸
  if (d.ambientEnabled == true &&
      strategy.immersion == ImmersionStrategy.restrained) {
    out.add('沉浸选了「克制」，又要求主动描写环境，可能会显得啰嗦。');
  }

  // 8) 斜体排版依赖 Markdown
  if (!strategy.formatMarkdown && strategy.formatActionItalic) {
    out.add('「旁白用斜体」依赖 Markdown，但 Markdown 是关闭的。');
  }

  // 9) 选了冲突来源却没设尺度上限
  if ((d.conflictPrimary != null || d.conflictSecondary != null) &&
      !strategy.hasIntensityLimit) {
    out.add('已经指定了冲突来源，但内容尺度还是「不限」，建议顺手定个上限。');
  }

  // 10) 母题频率大于每段
  if (d.motifName != null && d.motifEveryN != null && d.motifEveryN == 0) {
    out.add('意象母题的出现间隔填了 0，等于没有间隔，容易出现得过于频繁。');
  }

  return out;
}
