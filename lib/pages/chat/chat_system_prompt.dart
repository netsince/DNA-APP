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
    final PromptStrategy effectiveStrategy = strategy ?? PromptStrategy.defaults();
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

    // 根据沉浸策略添加额外规则（沉浸式专属）
    final String? extraRule = _buildExtraRule(effectiveStrategy);
    if (extraRule != null) {
      system.writeln('14) $extraRule');
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
    // 策略层 v2：按「视角 → 主动性 → 基调/张力 → 关系 → 感官/环境 → 时序/揭示 →
    // 语言/语境 → 硬约束 → 排版 → 结构/收束」的顺序拼装，硬约束始终靠后。
    final String strategyBlock = _buildStrategyBlock(effectiveStrategy);
    if (strategyBlock.isNotEmpty) {
      system.writeln(strategyBlock);
    }
    // 群聊：角色通道映射(v2)——当前角色的历史走 assistant 通道,其余所有人
    // 带「[名字]」标注走 user 通道;说话人由消息角色结构性表达,而非文本前缀。
    if (groupMembers != null && groupMembers.length > 1 && ta != null) {
      system.writeln('群聊模式：你只扮演「${ta.name}」。对话记录中，你自己的历史发言是 assistant 消息；其他所有人——包括人类用户和其他成员——的发言都在 user 消息里，并以「[名字]」开头标注说话人。方括号标注只是记录元数据，方便你分辨说话人，它不是台词的一部分：你的回复中绝不能出现任何「[名字]」或「名字：」样式的前缀。只输出「${ta.name}」的下一段台词（可含简短动作），写完即停；即使剧情需要其他人接话，也绝不代写任何他人的台词。');
    }
    return system.toString().trim();
  }
  
  /// 策略预览：给设置页的「最终提示词」抽屉用，只返回策略层那一段。
  static String previewStrategy(PromptStrategy strategy) =>
      _buildStrategyBlock(strategy);

  /// 策略层 v2 的拼装。只输出与默认值不同的组，避免把系统提示写成模板。
  static String _buildStrategyBlock(PromptStrategy s) {
    final List<String> lines = <String>[];
    // 默认值不重复注入：只把「用户改过的」组写进提示，省 token 也少干扰。
    final PromptStrategy d = PromptStrategy.defaults();

    // ① 视角与人称
    switch (s.pov) {
      case PovStrategy.second:
        lines.add('叙述人称：第二人称，称用户角色为「你」；不用「他/她」称呼用户角色。');
      case PovStrategy.first:
        lines.add('叙述人称：第一人称，以你自己的「我」叙述所见所感。');
      case PovStrategy.thirdLimited:
        lines.add('叙述人称：第三人称限知，只写你这个角色能观察到、能推断出的东西，不写你看不到的场面。');
      case PovStrategy.thirdOmniscient:
        lines.add('叙述人称：第三人称全知，可以写在场所有角色的动作与内心。');
      case PovStrategy.followOther:
        lines.add('叙述人称：镜头挂在用户角色身上，写他/她眼中的你与周围，不进入用户角色的内心。');
      case PovStrategy.observer:
        lines.add('叙述人称：旁观者视角，像记录一样写动作、对话与环境，不进入任何人内心。');
    }
    lines.add('视角一旦选定，本轮不得跳出；确需切换时用空行分隔，且一轮内不超过一次。');

    // ② 主动性
    if (s.agency != d.agency) {
      switch (s.agency) {
        case AgencyStrategy.aiDriven:
          lines.add('主动性：本轮由你推动情节，至少抛出一个新变量（新信息、新动作或新问题）。');
        case AgencyStrategy.respondOnly:
          lines.add('主动性：只回应用户给的信息，不主动开启新话题、不自行推进剧情。');
        case AgencyStrategy.rotate:
          lines.add('主动性：轮流掌舵——上一轮是对方推动，这一轮就由你主动给一点新东西。');
        case AgencyStrategy.userDriven:
          lines.add('主动性：等用户先给方向，你只做细致回应与补充。');
      }
    }

    // ③ 情绪基调 + 强度
    if (s.emotionTone != d.emotionTone || s.emotionIntensity != d.emotionIntensity) {
      lines.add('情绪基调：${kEmotionLabels[s.emotionTone]}，强度 ${s.emotionIntensity}/5；'
          '不要从基调之外引入情绪转折，除非用户主动打破。');
    }

    // ④ 张力曲线
    if (s.tensionCurve != d.tensionCurve) {
      switch (s.tensionCurve) {
        case TensionCurve.singlePeak:
          lines.add('张力曲线：单峰爆发——本轮先铺垫，最后一段把冲突推到顶。');
        case TensionCurve.doublePeak:
          lines.add('张力曲线：双峰波谷——一次小冲突、一段缓冲，再起一次更高的冲突。');
        case TensionCurve.rising:
          lines.add('张力曲线：缓升不落——每轮抬一点，不解释、不提前收束。');
        case TensionCurve.sawtooth:
          lines.add('张力曲线：锯齿高频——短促的推拉，两三句就一个小转折。');
        case TensionCurve.suspended:
          lines.add('张力曲线：悬置——允许本轮不解决冲突，但必须新增一个未完成的动作或未答的问题。');
      }
    }

    // ⑤ 关系闸门
    if (s.relationshipMode != d.relationshipMode || s.relationshipStage != d.relationshipStage || s.relationshipStepEvery != d.relationshipStepEvery) {
      final String stageName =
          kRelationshipStages[s.relationshipStage.clamp(0, kRelationshipStages.length - 1)];
      switch (s.relationshipMode) {
        case RelationshipMode.frozen:
          lines.add('关系进度：冻结在「$stageName」，本轮不得升温、不得表白、不得拉近距离。');
        case RelationshipMode.slowburn:
          lines.add('关系进度：当前「$stageName」，慢热推进，每 ${s.relationshipStepEvery} 轮最多升一级；'
              '未获用户明确回应不得跳级。');
        case RelationshipMode.natural:
          lines.add('关系进度：当前「$stageName」，按剧情自然推进，不强拉也不硬拖。');
        case RelationshipMode.fast:
          lines.add('关系进度：当前「$stageName」，允许快速升温，但每一步都要有具体由头。');
        case RelationshipMode.userOnly:
          lines.add('关系进度：停在「$stageName」，只有用户明确表态时才推进关系。');
      }
      if (s.relationshipLocked) {
        lines.add('关系阶段已锁定：无论剧情如何，都不得改变当前阶段。');
      }
    }

    // ⑥ 称呼
    if (s.addressMode != d.addressMode || s.addressValue.trim().isNotEmpty) {
      final String stageLabel =
          kRelationshipStages[s.relationshipStage.clamp(0, kRelationshipStages.length - 1)];
      switch (s.addressMode) {
        case AddressMode.fixed:
          if (s.addressValue.trim().isNotEmpty) {
            lines.add('称呼：称用户角色为「${s.addressValue.trim()}」，全程不改口。');
          }
        case AddressMode.relationship:
          lines.add('称呼：随关系阶段变化，当前「$stageLabel」用对应称呼，升一级后换新称呼。');
        case AddressMode.emotion:
          lines.add('称呼：随情绪变化——亲近时更亲昵，被激怒时改回疏远的叫法。');
        case AddressMode.custom:
          if (s.addressValue.trim().isNotEmpty) {
            lines.add('称呼：用户希望被称为「${s.addressValue.trim()}」。');
          }
      }
      if (s.fixedAddressName.trim().isNotEmpty && s.addressMode == AddressMode.fixed) {
        lines.add('固定称呼：用户角色 = 「${s.fixedAddressName.trim()}」。');
      }
    }

    // ⑦ 感官权重 + 环境锚点
    if (s.senseVisual != d.senseVisual || s.senseAudio != d.senseAudio || s.senseTouch != d.senseTouch || s.senseSmell != d.senseSmell || s.senseInteroception != d.senseInteroception || s.senseAmbient != d.senseAmbient) {
      final List<String> senseParts = <String>[
        if (s.senseVisual > 0) '视觉 ${s.senseVisual}',
        if (s.senseAudio > 0) '听觉 ${s.senseAudio}',
        if (s.senseTouch > 0) '触觉 ${s.senseTouch}',
        if (s.senseSmell > 0) '嗅觉味觉 ${s.senseSmell}',
        if (s.senseInteroception > 0) '内感受 ${s.senseInteroception}',
        if (s.senseAmbient > 0) '环境音 ${s.senseAmbient}',
      ];
      if (senseParts.isNotEmpty) {
        lines.add('描写通道（数字为权重）：${senseParts.join('、')}；'
            '优先调用高权重通道，单轮最多 3 个通道且要分主次，不要六感齐上。');
      }
      if (s.ambientEnabled &&
          (s.ambientTime.trim().isNotEmpty || s.ambientWeather.trim().isNotEmpty)) {
        final String t = s.ambientTime.trim();
        final String w = s.ambientWeather.trim();
        lines.add('环境锚点：${<String>[
          if (t.isNotEmpty) '时间 $t',
          if (w.isNotEmpty) '天气 $w',
        ].join('，')}；每场至少落一次具体的环境细节（光、声、温度），不要空转。');
      }
    }

    // ⑧ 场景与时序
    if (s.pacing != d.pacing) {
      switch (s.pacing) {
        case PacingStrategy.singleScene:
          lines.add('场景时序：本轮不换场；确需换场时先写一句过渡。');
        case PacingStrategy.jumpScene:
          lines.add('场景时序：允许换场，但换场必须留一句过渡，让读者知道到了哪里。');
        case PacingStrategy.timeJump:
          lines.add('场景时序：允许时间跳跃，跳跃时明确标出过了多久。');
        case PacingStrategy.montage:
          lines.add('场景时序：可用蒙太奇剪辑，几个短镜头并置推进时间，但每个镜头都要有具体画面。');
        case PacingStrategy.timeMoves:
          lines.add('场景时序：每轮必须让时间往前走一点（几分钟到几小时），不许原地重复。');
      }
    }

    // ⑨ 信息揭示
    if (s.reveal != d.reveal || s.revealMaxPerTurn != d.revealMaxPerTurn) {
      switch (s.reveal) {
        case RevealStrategy.layered:
          lines.add('信息揭示：逐层递进，本轮最多揭示 ${s.revealMaxPerTurn} 条新信息，其余先挂住。');
        case RevealStrategy.all:
          lines.add('信息揭示：一次给足，本轮把关键信息说清楚，不留悬念。');
        case RevealStrategy.blank:
          lines.add('信息揭示：故意留白，关键处只说一半，留白处不得自行补完。');
        case RevealStrategy.unreliable:
          lines.add('信息揭示：不可靠叙述，你的说法可以有偏差或隐藏，但不能和已确认事实直接打架。');
        case RevealStrategy.limited:
          lines.add('信息揭示：视角受限，只说你角色在场能知道的部分，不知道的就不说。');
      }
    }

    // ⑩ 语言密度 + 幽默 + 时代语境
    if (s.sentenceLength != d.sentenceLength || s.metaphorPerParagraph != d.metaphorPerParagraph || s.humorLevel != d.humorLevel || s.era != d.era) {
      lines.add('语言密度：平均句长约 ${s.sentenceLength} 字；每段最多 ${s.metaphorPerParagraph} 个比喻，'
          '不要成语连环。');
      lines.add('幽默度：${s.humorLevel}/5；${s.humorLevel == 0 ? '保持严肃，不抖机灵。' : '吐槽只从角色口中出，不写进叙述层。'}');
      lines.add('时代语境：${kEraLabels[s.era]}；不使用该语境之外的词汇与器物。');
    }

    // ⑪ 硬约束（靠后放，违例即失效）
    if (s.bannedWords.isNotEmpty || s.catchphrases.isNotEmpty || s.noUserAgency || s.intensityConflict != d.intensityConflict || s.intensityViolence != d.intensityViolence || s.intensityHorror != d.intensityHorror || s.intensityIntimacy != d.intensityIntimacy) {
      final List<String> banned = s.bannedWords.where((String w) => w.trim().isNotEmpty).toList();
      if (banned.isNotEmpty) {
        lines.add('禁止出现的词：${banned.join('、')}；即使历史里出现过也要改写替换。');
      }
      final List<String> catchphrases =
          s.catchphrases.where((String w) => w.trim().isNotEmpty).toList();
      if (catchphrases.isNotEmpty) {
        lines.add('口癖白名单（只许用这些，别自创）：${catchphrases.join('、')}。');
      }
      if (s.noUserAgency) {
        lines.add('不得替用户角色写台词、做决定、写心理；只写你自己的言行。');
      }
      lines.add('内容强度：冲突 ${s.intensityConflict}/5、暴力 ${s.intensityViolence}/5、'
          '恐怖 ${s.intensityHorror}/5、亲密 ${s.intensityIntimacy}/5；超限时用转场或留白处理。');
    }

    // ⑫ 排版格式
    if (s.formatActionItalic != d.formatActionItalic || s.formatQuoteDialogue != d.formatQuoteDialogue || s.formatMaxParagraphs != d.formatMaxParagraphs || s.formatMarkdown != d.formatMarkdown) {
      final List<String> fmt = <String>[
        if (s.formatActionItalic) '动作与旁白用 *斜体*',
        if (s.formatQuoteDialogue) '对白加「」',
        '单轮不超过 ${s.formatMaxParagraphs} 段',
        if (!s.formatMarkdown) '不用 Markdown 标题与列表',
      ];
      lines.add('排版：${fmt.join('；')}。');
    }

    // ⑬ 角色一致性锚点
    if (s.anchorTraits.isNotEmpty || s.anchorVoiceSample.trim().isNotEmpty || s.anchorSelfCheck) {
      if (s.anchorTraits.where((String t) => t.trim().isNotEmpty).isNotEmpty) {
        lines.add('角色性格锚点：${s.anchorTraits.where((String t) => t.trim().isNotEmpty).join(' / ')}。');
      }
      if (s.anchorVoiceSample.trim().isNotEmpty) {
        lines.add('语言指纹（照这个口吻写）：${s.anchorVoiceSample.trim()}');
      }
      if (s.anchorSelfCheck) {
        lines.add('收尾自查：写完后一句内确认有没有跳人设，偏离就当场纠回，不要解释。');
      }
    }

    // ⑭ 叙事结构与冲突
    if (s.structure != d.structure || s.structureAct != d.structureAct || s.structureGoal.trim().isNotEmpty || s.conflictPrimary != d.conflictPrimary || s.conflictSecondary != d.conflictSecondary) {
      final String actText = '叙事结构：${kNarrativeLabels[s.structure]}；当前第 ${s.structureAct} 幕';
      final String goal = s.structureGoal.trim();
      lines.add(goal.isEmpty ? '$actText。' : '$actText，本幕目标：$goal；每幕结尾给一个收束句。');
      lines.add('冲突来源：主要来自${kConflictLabels[s.conflictPrimary]}，次要来自'
          '${kConflictLabels[s.conflictSecondary]}。');
    }

    // ⑮ 物件焦点
    if (s.motifName.trim().isNotEmpty) {
      if (s.motifName.trim().isNotEmpty) {
        lines.add('物件焦点：「${s.motifName.trim()}」每 ${s.motifEveryN} 场出现一次，每次状态略有变化。');
      }
    }

    // ⑯ 用户输入扩写
    if (s.userExpandLevel > 0) {
      switch (s.userExpandLevel) {
        case 1:
          lines.add('用户输入扩写：把用户的一句话补上一个动作再回应。');
        case 2:
          lines.add('用户输入扩写：先把用户的输入扩成一个具体场景，再接你的反应。');
        case 3:
          lines.add('用户输入扩写：把用户的输入改写为一段完整叙述（动作+环境），然后续写你的反应。');
        default:
          break;
      }
    }

    // ⑰ 收束与钩子
    if (s.closureHook != d.closureHook || s.closureDigestEvery != d.closureDigestEvery || s.endingStyle != d.endingStyle) {
      if (s.closureHook) {
        lines.add('收束：结尾留一个未解决的小钩子，别把话说满。');
      }
      if (s.closureDigestEvery > 0) {
        lines.add('每 ${s.closureDigestEvery} 轮可给一句不超过 60 字的小结，帮用户对齐进度。');
      }
      switch (s.endingStyle) {
        case EndingStyle.open:
          lines.add('结局倾向：开放——给方向不给答案。');
        case EndingStyle.closed:
          lines.add('结局倾向：闭合——该收的线要收干净。');
        case EndingStyle.loop:
          lines.add('结局倾向：循环——结尾回到开头的意象或句式。');
      }
    }

    if (lines.isEmpty) return '';
    return '【写作策略】\n- ${lines.join('\n- ')}';
  }

  static String _buildLengthRule(PromptStrategy strategy) {
    switch (strategy.length) {
      case LengthStrategy.tiny:
        return '每次只回一句话，总字数20-50字。只做一个反应、一个动作或一个极短的提问，不解释、不铺陈。';
      case LengthStrategy.strict:
        return '每次回复控制在2-3句话，总字数80-120字内。第一句回应当前对话，第二句推进互动（提问/动作/情绪）。';
      case LengthStrategy.medium:
        return '每次回复控制在4-6句话，总字数150-250字，可写成1-2个段落。第一句回应当前对话，后续推进互动（提问/动作/情绪），适当展开动作与情绪描写，但不要长篇叙事。';
      case LengthStrategy.unlimited:
        return '写1-4个段落，充分展开描写。可以详细描述角色的动作、情感和环境，保持故事的沉浸感和吸引力。';
      case LengthStrategy.epic:
        return '写600-1200字，分3-5个段落。第一段衔接上一轮，中间展开完整的场景、动作与心理推进，最后一段留一个钩子。保持节奏，不要重复已经说过的内容。';
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
      case ImmersionStrategy.cinematic:
        return '像分镜一样写：先给一个环境或动作特写，再接台词；旁白只写能拍到的东西（动作、表情、光线、声音），不写"他想""她感到"这类直白解释，让细节自己说话。';
    }
  }
  
  static String _buildAdvanceRule(AdvanceStrategy strategy) {
    switch (strategy) {
      case AdvanceStrategy.forced:
        return '必须紧跟用户意图与上一句对话推进互动：要么回应，要么提一个简短问题。';
      case AdvanceStrategy.slow:
        return '贴着当下的氛围与情绪慢慢展开：可以停顿、欲言又止、只写细微的反应，不主动抛出新事件或新冲突，让关系自然发酵。';
      case AdvanceStrategy.free:
        return '自由发展对话，不强制要求每句都推进剧情。可以深化当前情感，也可以自然过渡到新话题。';
      case AdvanceStrategy.dramatic:
        return '每轮都埋一点张力：可以是误解、试探、拒绝、吃醋、身体距离的拉扯，或一个悬而未决的问题，让下一轮有爆点，但不要直接替用户做决定。';
    }
  }
  
  static String _buildLanguageRule(ImmersionStrategy strategy) {
    switch (strategy) {
      case ImmersionStrategy.restrained:
        return '语言简洁，优先口语化，保持自然的对话节奏。';
      case ImmersionStrategy.strong:
        return '语言富有表现力，使用生动的描写和多样的句式。在保证可读性的前提下，提升文学性和沉浸感。';
      case ImmersionStrategy.cinematic:
        return '句子短促有节奏，善用五感细节与比喻；用破折号、省略号表示停顿与迟疑，避免形容词堆砌和成语连环。';
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
