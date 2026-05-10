import '../../models/dialogue_style.dart';
import '../../models/prompt_strategy.dart';
import '../../models/ta.dart';
import '../../models/world.dart';

class ChatSystemPrompt {
  static String build({
    required TA? ta,
    required World? world,
    String? groupPrompt,
    PromptStrategy? strategy,
  }) {
    final List<DialogueTurn> style = ta?.dialogueStyle ?? <DialogueTurn>[];
    final PromptStrategy effectiveStrategy = strategy ?? PromptStrategy.defaults();
    final StringBuffer system = StringBuffer();
    
    system.writeln('你是"TA扮演对话"模式。必须严格遵守以下规则：');
    system.writeln('1) 括号"（…）"为旁白，只用于动作、表情、内心或环境描写，且尽量简短。');
    
    // 根据字数策略生成规则2
    final String lengthRule = _buildLengthRule(effectiveStrategy.length);
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
    
    // 根据沉浸策略添加额外规则（沉浸式专属）
    final String? extraRule = _buildExtraRule(effectiveStrategy);
    if (extraRule != null) {
      system.writeln('13) $extraRule');
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
    if (groupPrompt != null && groupPrompt.trim().isNotEmpty) {
      system.writeln('缇よ瀹氾細${groupPrompt.trim()}');
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
    return system.toString().trim();
  }
  
  static String _buildLengthRule(LengthStrategy strategy) {
    switch (strategy) {
      case LengthStrategy.strict:
        return '每次回复控制在2-3句话，总字数80-120字内。第一句回应当前对话，第二句推进互动（提问/动作/情绪）。';
      case LengthStrategy.unlimited:
        return '写1-4个段落，充分展开描写。可以详细描述角色的动作、情感和环境，保持故事的沉浸感和吸引力。';
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
  
  static String? _buildExtraRule(PromptStrategy strategy) {
    // 当选择无限制字数 + 强沉浸时，添加类似 Roleplay - Immersive 的系统注释
    if (strategy.length == LengthStrategy.unlimited && 
        strategy.immersion == ImmersionStrategy.strong) {
      return '[系统注释：充分沉浸角色，提供丰富的感官细节和情感层次。不要重复此消息。]';
    }
    return null;
  }
}
