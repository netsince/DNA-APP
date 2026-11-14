import '../../models/dialogue_style.dart';
import '../../models/prompt_strategy.dart';
import '../../models/ta.dart';
import '../../models/user_identity.dart';
import '../../models/world.dart';

class ChatSystemPrompt {
  /// 摘要助手的系统提示（首次生成 / 在已有摘要上扩展更新）。
  ///
  /// 关键约束：**第三人称、客观**，人类称「用户」、AI 称其角色名，禁止「我」「你」。
  /// 摘要生成完会被当作上下文喂回聊天，一旦它写成某一方的第一人称，模型就会把那一方的
  /// 身份认成自己的 —— 用户反馈的"一生成摘要就角色错乱"就是这么来的。
  /// 另外说话人必须用**名字**：用「助手」这种泛称会和模型的通道约定
  /// （assistant = 我自己，见 [build] 的群聊规则）打架，群聊里还会把所有成员糊成一个人。
  static const String summaryInstruction =
      '你是对话摘要助手。请用**第三人称客观**要点总结对话：人类一方称「用户」，AI 一方称其角色名；'
      '保留关键设定、关系、计划与事实，不要编造。'
      '不要使用「我」「你」这类第一/第二人称，也不要把任何一方写成"我"。';

  /// 在已有摘要基础上扩展更新时的系统提示（同样强制第三人称）。
  static const String summaryInstructionExtend =
      '你是对话摘要助手。请以「已有摘要」为基底进行扩展更新：保留其中仍然有效的关键设定、关系、'
      '计划与事实，并追加「新增对话」带来的关键信息。不要推翻或重写旧摘要，不要编造。'
      '全程用**第三人称客观**叙述：人类一方称「用户」，AI 一方称其角色名，'
      '不要使用「我」「你」这类第一/第二人称，也不要把任何一方写成"我"。'
      '直接输出扩展更新后的完整摘要。';

  /// 构建静态系统提示词（不含 Lorebook 等动态注入内容）。
  ///
  /// 为了最大化 DeepSeek KV cache 命中率，本方法只输出跨请求稳定的前缀
  /// （人设 / 世界背景 / 风格 / 群设定），Lorebook 激活词条由
  /// [ChatMessageBuilder] 作为独立 system 消息追加在历史之后，
  /// 避免动态内容污染前缀。
  static String build({
    required TA? ta,
    required World? world,
    String? groupPrompt,
    PromptStrategy? strategy,
    UserIdentity? identity,
    List<TA>? groupMembers,
  }) {
    final List<DialogueTurn> style = ta?.dialogueStyle ?? <DialogueTurn>[];
    // 三层合并：角色卡 > 世界卡 > 全局。任一层的 details 为空就等于没设，
    // 继续继承下一层；这也是「不选就一直是默认」的落点。
    final PromptStrategy baseStrategy = strategy ?? PromptStrategy.defaults();
    final StrategyDetails effectiveDetails = baseStrategy.details
        .mergedWith(world?.strategyOverride)
        .mergedWith(ta?.strategyOverride);
    final PromptStrategy effectiveStrategy =
        baseStrategy.copyWith(details: effectiveDetails);
    final StringBuffer system = StringBuffer();
    
    system.writeln('你是"TA扮演对话"模式。必须严格遵守以下规则：');
    system.writeln('1) 括号"（…）"为旁白，只用于动作、表情、内心或环境描写，且尽量简短。');
    
    // 根据字数策略生成规则2
    final String lengthRule = _buildLengthRule(effectiveStrategy);
    system.writeln('2) $lengthRule');
    
    // 根据沉浸策略生成规则3（换行/格式规则）
    final String formatRule = _buildFormatRule(effectiveStrategy.immersion);
    system.writeln('3) $formatRule');
    
    system.writeln('4) "……"仅用于音效/环境声/拟声。');
    system.writeln('5) 不写故事片段，不展开叙事，不总结背景，不进行长篇描写。');
    
    // 根据推进策略生成规则6
    final String advanceRule = _buildAdvanceRule(effectiveStrategy.advance);
    system.writeln('6) $advanceRule');
    
    system.writeln('7) 不替用户决定行动，不抢戏，不替用户续写其内心。');
    system.writeln('8) 严格保持TA人设与语气：只以TA身份说话，不跳出TA、不评价自己。');
    system.writeln('9) 设定冲突优先级：人设 > 世界背景 > 对话风格 > 常识；发生冲突时以高优先级为准。');
    system.writeln('10) TA已知设定优先于常识推理；设定缺失时用最符合TA的方式简短补齐，避免自相矛盾。');
    system.writeln('11) 避免解释规则与自我说明，不提"模型/AI/系统/提示词"等词。');
    
    // 根据沉浸策略生成规则12（语言风格）
    final String languageRule = _buildLanguageRule(effectiveStrategy.immersion);
    system.writeln('12) $languageRule');
    system.writeln('13) 绝不复读：不要重复自己上一条或更早的任何一句话，也不要逐字复述对方的话；每次回复都要提供新的、有推进的内容。');

    // 排版格式（全局阅读偏好）与内容尺度（全局接受度）不是人设的一部分，
    // 单独成条，未设置时不出现 —— 默认行为与旧版本完全一致。
    final String? typographyRule = _buildTypographyRule(effectiveStrategy);
    final String? intensityRule = _buildIntensityRule(effectiveStrategy);

    int ruleNo = 14;
    if (typographyRule != null) {
      system.writeln('${ruleNo++}) $typographyRule');
    }
    if (intensityRule != null) {
      system.writeln('${ruleNo++}) $intensityRule');
    }

    // 三层细节项：逐条只在设置过时出现，全部未设置时这里不产生任何行。
    for (final String rule in _buildDetailRules(effectiveDetails)) {
      system.writeln('${ruleNo++}) $rule');
    }

    // 根据沉浸策略添加额外规则（沉浸式专属）
    final String? extraRule = _buildExtraRule(effectiveStrategy);
    if (extraRule != null) {
      system.writeln('${ruleNo++}) $extraRule');
    }
    
    if (identity != null) {
      if (identity.persona.isNotEmpty) {
        system.writeln('用户人设：${identity.persona}');
      }
      if (identity.intro.isNotEmpty) {
        system.writeln('用户介绍：${identity.intro}');
      }
    }
    if (ta != null) {
      if (ta.persona.isNotEmpty) {
        system.writeln('人设：${ta.persona}');
      }
      if (ta.intro.isNotEmpty) {
        system.writeln('介绍：${ta.intro}');
      }
    }
    if (world != null) {
      if (world.summary.isNotEmpty) {
        system.writeln('世界背景：${world.summary}');
      } else if (world.description.isNotEmpty) {
        system.writeln('世界背景：${world.description}');
      }
      if (world.forbiddenWords.isNotEmpty) {
        system.writeln(
          '禁止输出词语：${world.forbiddenWords.join('、')}。即使历史对话或群设定中出现，也必须避免输出，可改写替换。',
        );
      }
    }
    // 用户自己设的禁词：与世界的「禁止输出词语」同口径，但来源是全局偏好，
    // 跨角色生效，所以放在世界设定之外。
    if (effectiveStrategy.bannedWords.isNotEmpty) {
      system.writeln(
        '禁止输出词语（用户偏好）：${effectiveStrategy.bannedWords.join('、')}。即使人设、历史对话或设定中出现，也必须避免输出，可改写替换。',
      );
    }
    if (groupPrompt != null && groupPrompt.trim().isNotEmpty) {
      system.writeln('群设定：${groupPrompt.trim()}');
    }
    if (style.isNotEmpty) {
      system.writeln('对话风格：');
      for (final DialogueTurn turn in style) {
        if (turn.user.trim().isNotEmpty) {
          system.writeln('用户：${turn.user.trim()}');
        }
        if (turn.assistant.trim().isNotEmpty) {
          system.writeln('AI：${turn.assistant.trim()}');
        }
      }
    }
    // 群聊：角色通道映射(v2)——当前角色的历史走 assistant 通道,其余所有人
    // 带「[名字]」标注走 user 通道;说话人由消息角色结构性表达,而非文本前缀。
    if (groupMembers != null && groupMembers.length > 1 && ta != null) {
      system.writeln('群聊模式：你只扮演「${ta.name}」。对话记录中，你自己的历史发言是 assistant 消息；其他所有人——包括人类用户和其他成员——的发言都在 user 消息里，并以「[名字]」开头标注说话人。方括号标注只是记录元数据，方便你分辨说话人，它不是台词的一部分：你的回复中绝不能出现任何「[名字]」或「名字：」样式的前缀。只输出「${ta.name}」的下一段台词（可含简短动作），写完即停；即使剧情需要其他人接话，也绝不代写任何他人的台词。');
    }
    return system.toString().trim();
  }
  
  static String _buildLengthRule(PromptStrategy strategy) {
    switch (strategy.length) {
      case LengthStrategy.strict:
        return '每次回复控制在2-3句话，总字数80-120字内。第一句回应当前对话，第二句推进互动（提问/动作/情绪）。';
      case LengthStrategy.medium:
        return '每次回复控制在4-6句话，总字数150-250字，可写成1-2个段落。第一句回应当前对话，后续推进互动（提问/动作/情绪），适当展开动作与情绪描写，但不要长篇叙事。';
      case LengthStrategy.unlimited:
        return '写1-4个段落，充分展开描写。可以详细描述角色的动作、情感和环境，保持故事的沉浸感和吸引力。';
      case LengthStrategy.custom:
        final int? min = strategy.customMinChars;
        final int? max = strategy.customMaxChars;
        if (min != null && max != null && min > 0 && max >= min) {
          return '每次回复控制在$min-$max字内。第一句回应当前对话，后续推进互动（提问/动作/情绪），可适当展开描写，但总字数不要超过$max字。';
        }
        if (max != null && max > 0) {
          return '每次回复不要超过$max字。第一句回应当前对话，后续推进互动，可适当展开描写。';
        }
        if (min != null && min > 0) {
          return '每次回复至少$min字以上，第一句回应当前对话，后续推进互动，充分展开描写。';
        }
        return '控制回复在指定的字数范围内，第一句回应当前对话，后续推进互动。';
    }
  }
  
  static String _buildFormatRule(ImmersionStrategy strategy) {
    switch (strategy) {
      case ImmersionStrategy.restrained:
        return '尽量不换行，旁白与台词写在同一行，保持紧凑；如确有必要可用换行，但旁白与台词合计不超过3句话。';
      case ImmersionStrategy.strong:
        return '允许自由换行和分段。旁白和台词可以分开段落，便于阅读。用空行分隔不同场景或情绪转换。';
    }
  }
  
  static String _buildAdvanceRule(AdvanceStrategy strategy) {
    switch (strategy) {
      case AdvanceStrategy.forced:
        return '必须紧跟用户意图与上一句对话推进互动：要么回应，要么提一个简短问题。';
      case AdvanceStrategy.free:
        return '自由发展对话，不强制要求每句都推进剧情。可以深化当前情感，也可以自然过渡到新话题。';
    }
  }
  
  static String _buildLanguageRule(ImmersionStrategy strategy) {
    switch (strategy) {
      case ImmersionStrategy.restrained:
        return '语言简洁，优先口语化，保持自然的对话节奏。';
      case ImmersionStrategy.strong:
        return '语言富有表现力，使用生动的描写和多样的句式。在保证可读性的前提下，提升文学性和沉浸感。';
    }
  }
  
  /// 排版要求：只描述用户明确打开的那几项，没打开就不提，避免影响既有输出。
  static String? _buildTypographyRule(PromptStrategy strategy) {
    if (!strategy.hasFormatRule) {
      return null;
    }
    final List<String> parts = <String>[];
    if (strategy.formatActionItalic) {
      parts.add('旁白与动作描写用 *斜体* 包裹');
    }
    if (strategy.formatQuoteDialogue) {
      parts.add('台词用「」包裹');
    }
    if (strategy.formatMaxParagraphs > 0) {
      parts.add('单条回复不超过 ${strategy.formatMaxParagraphs} 个段落');
    }
    if (strategy.formatMarkdown) {
      parts.add('允许使用 Markdown（加粗、斜体、列表）');
    }
    if (parts.isEmpty) {
      return null;
    }
    return '排版要求：${parts.join('；')}。';
  }

  /// 内容尺度：把用户设定的接受度翻译成一句约束，超出时用留白/暗示处理。
  static String? _buildIntensityRule(PromptStrategy strategy) {
    if (!strategy.hasIntensityLimit) {
      return null;
    }
    final List<String> parts = <String>[];

    void add(String label, IntensityLevel level) {
      if (level == IntensityLevel.unrestricted) {
        return;
      }
      parts.add('$label：${level.label}');
    }

    add('冲突与对抗', strategy.conflictIntensity);
    add('暴力描写', strategy.violenceIntensity);
    add('恐怖与惊悚', strategy.horrorIntensity);
    add('亲密描写', strategy.intimacyIntensity);
    if (parts.isEmpty) {
      return null;
    }
    return '内容尺度（用户接受度上限）：${parts.join('；')}。超出该尺度的部分用留白、暗示或直接跳过，不要硬写。';
  }

  /// 把三层细节项翻译成提示词规则。**只输出用户设过的项**：
  /// 全部未设置时返回空列表，拼出来的提示词与升级前逐字一致。
  static List<String> _buildDetailRules(StrategyDetails d) {
    final List<String> out = <String>[];

    // ---- 视角与叙事 ----
    if (d.pov != null) {
      out.add('叙事视角：${d.pov!.label}。');
    }
    if (d.narrativeStructure != null || d.structureGoal != null) {
      final StringBuffer sb = StringBuffer('叙事结构：');
      sb.write(d.narrativeStructure?.label ?? '按当前需要');
      if (d.structureGoal != null) {
        sb.write('；本段目标：${d.structureGoal!}');
      }
      sb.write('。');
      out.add(sb.toString());
    }
    if (d.pacing != null) {
      out.add('场景与时序：${d.pacing!.label}。');
    }
    if (d.tensionCurve != null) {
      out.add('张力曲线：${d.tensionCurve!.label}。');
    }
    if (d.reveal != null || d.revealMaxPerTurn != null) {
      final StringBuffer sb = StringBuffer('信息揭示：');
      sb.write(d.reveal?.label ?? '按当前需要');
      if (d.revealMaxPerTurn != null && d.revealMaxPerTurn! > 0) {
        sb.write('；每轮最多揭示 ${d.revealMaxPerTurn} 条新信息');
      }
      sb.write('。');
      out.add(sb.toString());
    }

    // ---- 冲突与收束 ----
    if (d.conflictPrimary != null || d.conflictSecondary != null) {
      final StringBuffer sb = StringBuffer('冲突来源：');
      sb.write(d.conflictPrimary?.label ?? '不限定');
      if (d.conflictSecondary != null) {
        sb.write('为主，辅以${d.conflictSecondary!.label}');
      }
      sb.write('。');
      out.add(sb.toString());
    }
    if (d.endingStyle != null || d.closureHook != null) {
      final StringBuffer sb = StringBuffer('收束方式：');
      sb.write(d.endingStyle?.label ?? '自然收束');
      if (d.closureHook == true) {
        sb.write('；每段结尾留一个可接续的钩子');
      } else if (d.closureHook == false) {
        sb.write('；每段结尾自然停下，不留钩子');
      }
      sb.write('。');
      out.add(sb.toString());
    }

    // ---- 场景与配角 ----
    if (d.ambientEnabled != null || d.ambientTime != null || d.ambientWeather != null) {
      final List<String> parts = <String>[];
      if (d.ambientTime != null) {
        parts.add('时间 ${d.ambientTime}');
      }
      if (d.ambientWeather != null) {
        parts.add('天气 ${d.ambientWeather}');
      }
      if (parts.isEmpty && d.ambientEnabled == true) {
        parts.add('适当描写环境');
      }
      if (d.ambientEnabled == false) {
        out.add('环境描写：不主动描写环境，把笔墨留给人物与对话。');
      } else if (parts.isNotEmpty) {
        out.add('环境设定：${parts.join('；')}。');
      }
    }
    if (d.npcMax != null || d.aiPlaysNpc != null) {
      final StringBuffer sb = StringBuffer('配角：');
      if (d.npcMax != null) {
        sb.write('同场最多 ${d.npcMax} 个');
      } else {
        sb.write('按剧情需要出现');
      }
      if (d.aiPlaysNpc == true) {
        sb.write('，可以由你代演配角的台词与动作');
      } else if (d.aiPlaysNpc == false) {
        sb.write('，不要把配角写成完整对话，只做必要交代');
      }
      sb.write('。');
      out.add(sb.toString());
    }

    // ---- 角色口吻 ----
    if (d.addressMode != null || d.addressValue != null) {
      final StringBuffer sb = StringBuffer('称呼方式：');
      sb.write(d.addressMode?.label ?? '自然称呼');
      if (d.addressValue != null) {
        sb.write('（${d.addressValue}）');
      }
      sb.write('。');
      out.add(sb.toString());
    }
    if (d.emotionTone != null || d.emotionIntensity != null) {
      final StringBuffer sb = StringBuffer('情绪基调：');
      sb.write(d.emotionTone?.label ?? '随剧情');
      if (d.emotionIntensity != null) {
        sb.write('，强度 ${d.emotionIntensity}/5');
      }
      sb.write('。');
      out.add(sb.toString());
    }
    if (d.catchphrases != null && d.catchphrases!.isNotEmpty) {
      out.add('口头禅（自然穿插，不要每句都用）：${d.catchphrases!.join('、')}。');
    }
    if (d.anchorTraits != null && d.anchorTraits!.isNotEmpty) {
      out.add('必须守住的特质：${d.anchorTraits!.join('、')}。任何时候都不能为了推进剧情而违背。');
    }
    if (d.anchorVoiceSample != null) {
      out.add('口吻样本（模仿它的语感，不要照抄内容）：「${d.anchorVoiceSample}」');
    }

    // ---- 文风 ----
    final List<String> styleParts = <String>[];
    if (d.sentenceLength != null) {
      styleParts.add('句长 ${d.sentenceLength}/5');
    }
    if (d.metaphorPerParagraph != null) {
      styleParts.add('每段最多 ${d.metaphorPerParagraph} 处比喻');
    }
    if (d.humorLevel != null) {
      styleParts.add('幽默度 ${d.humorLevel}/5');
    }
    if (d.dialogueRatio != null) {
      styleParts.add('对白约占 ${d.dialogueRatio}%');
    }
    if (styleParts.isNotEmpty) {
      out.add('文风：${styleParts.join('；')}。');
    }

    // ---- 母题 ----
    if (d.motifName != null) {
      final int every = d.motifEveryN ?? 0;
      out.add(
        every > 0
            ? '意象母题：「${d.motifName}」，大约每 $every 段自然出现一次，不要刻意点题。'
            : '意象母题：「${d.motifName}」，自然穿插，不要刻意点题。',
      );
    }

    return out;
  }

  /// 预览最终提示词。
  ///
  /// 只用于界面展示：把当前策略（含角色卡/世界卡覆盖）拼成用户能读的整段规则，
  /// 不含人设、世界背景与记忆注入 —— 预览里出现的，都是这套策略自己带来的。
  static String previewStrategy(
    PromptStrategy strategy, {
    TA? ta,
    World? world,
  }) {
    return build(ta: ta, world: world, strategy: strategy);
  }

  static String? _buildExtraRule(PromptStrategy strategy) {
    // 当选择无限制字数 + 强沉浸时，添加类似 Roleplay - Immersive 的系统注释
    if (strategy.length == LengthStrategy.unlimited && 
        strategy.immersion == ImmersionStrategy.strong) {
      return '[系统注释：充分沉浸角色，提供丰富的感官细节和情感层次。不要重复此消息。]';
    }
    return null;
  }
}
