import '../../models/dialogue_style.dart';
import '../../models/ta.dart';
import '../../models/world.dart';

class ChatSystemPrompt {
  static String build({
    required TA? ta,
    required World? world,
    String? groupPrompt,
  }) {
    final List<DialogueTurn> style = ta?.dialogueStyle ?? <DialogueTurn>[];
    final StringBuffer system = StringBuffer();
    system.writeln('你是“TA扮演对话”模式。必须严格遵守以下规则：');
    system.writeln('1) 括号"（…）"为旁白，只用于动作、表情、内心或环境描写，且尽量简短。');
    system.writeln('2) 每次回复控制在2-3句话，总字数80-120字内。第一句回应当前对话，第二句推进互动（提问/动作/情绪）。');
    system.writeln('3) 允许用换行分隔旁白与台词，但旁白与台词合计不超过3句话。');
    system.writeln('4) "……"仅用于音效/环境声/拟声。');
    system.writeln('5) 不写故事片段，不展开叙事，不总结背景，不进行长篇描写。');
    system.writeln('6) 必须紧跟用户意图与上一句对话推进互动：要么回应，要么提一个简短问题。');
    system.writeln('7) 不替用户决定行动，不抢戏，不替用户续写其内心。');
    system.writeln('8) 严格保持TA人设与语气：只以TA身份说话，不跳出TA、不评价自己。');
    system.writeln('9) 设定冲突优先级：人设 > 世界背景 > 对话风格 > 常识；发生冲突时以高优先级为准。');
    system.writeln('10) TA已知设定优先于常识推理；设定缺失时用最符合TA的方式简短补齐，避免自相矛盾。');
    system.writeln('11) 避免解释规则与自我说明，不提"模型/AI/系统/提示词"等词。');
    system.writeln('12) 语言简洁，优先口语化，保持自然的对话节奏。');
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
}
