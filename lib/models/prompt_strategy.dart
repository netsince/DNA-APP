/// 提示词策略 v2：从「怎么写」扩展到「谁在说、写到哪、写到什么程度」。
///
/// 设计依据见项目内《提示词策略面板 · 扩展方案 v2》：把原来三组（推进 / 沉浸 / 字数）
/// 扩到二十余组，并按「预设胶囊 → 六条主轴 → 高级细项」三层交互呈现。
/// 兼容旧数据：v1 的 advance / immersion / length 三个键仍然照读照写。
library;

enum AdvanceStrategy {
  forced,

  /// 慢热细腻：围绕当下场景与情绪逐步展开，不主动抛出新事件。
  slow,
  free,

  /// 冲突张力：主动制造误解、阻碍与悬念，让对话更有戏。
  dramatic,
}

enum ImmersionStrategy {
  restrained,
  strong,

  /// 电影感：以镜头语言写环境与动作，少做直白心理总结。
  cinematic,
}

enum LengthStrategy {
  /// 极简：一句话、20-50 字。
  tiny,
  strict,
  medium,
  unlimited,

  /// 长篇：600-1200 字，分 3-5 段。
  epic,
  custom,
}

/// 视角与人称。
enum PovStrategy {
  /// 第二人称「你」：叙述里直接称用户为「你」。
  second,

  /// 第一人称「我」：AI 以角色自身的「我」叙述。
  first,

  /// 第三人称限知：只写该角色能观察到的东西。
  thirdLimited,

  /// 第三人称全知：可写所有人内心。
  thirdOmniscient,

  /// 跟随对手角色：镜头挂在用户角色身上，写他/她看到的对方。
  followOther,

  /// 旁观者：像旁白一样客观记录，不进入任何人的内心。
  observer,
}

/// 张力曲线形状（与「剧情推进」的力度互补）。
enum TensionCurve {
  singlePeak,
  doublePeak,
  rising,
  sawtooth,
  suspended,
}

/// 关系推进闸门。
enum RelationshipMode {
  /// 冻结：关系停在当前阶段。
  frozen,

  /// 慢热：每 N 轮升一级。
  slowburn,

  /// 自然：按剧情节奏推进。
  natural,

  /// 快进：允许快速升温。
  fast,

  /// 仅用户显式解锁：不主动推进。
  userOnly,
}

/// 场景与时序。
enum PacingStrategy {
  singleScene,
  jumpScene,
  timeJump,
  montage,
  timeMoves,
}

/// 信息揭示策略。
enum RevealStrategy { layered, all, blank, unreliable, limited }

/// 主动性分配：谁握方向盘。
enum AgencyStrategy { aiDriven, respondOnly, rotate, userDriven }

/// 情绪基调。
enum EmotionTone { distant, warm, danger, blackHumor, suspense, sweet }

/// 叙事结构。
enum NarrativeStructure { threeAct, chapters, slice, loop, epistolary }

/// 冲突来源。
enum ConflictType {
  interpersonal,
  environment,
  inner,
  timePressure,
  institution,
  information,
}

/// 时代与语境（防时代错位）。
enum EraSetting { modern, nearFuture, fantasy, academy, workplace, wilderness }

/// 称呼系统。
enum AddressMode { fixed, relationship, emotion, custom }

/// 结局收束方式。
enum EndingStyle { open, closed, loop }

/// 采样与创意度（不进 prompt，供「模型参数」参考）。
enum SamplingPreset { strict, standard, vivid, wild }

/// 预设胶囊：一次点选就把二十余组配好，用户不必逐项调。
enum StrategyPreset {
  cinematic('电影感', '镜头感、慢推、光影细节，适合沉浸向长对话'),
  webnovel('网文爽', '强推进、高张力、台词短促，节奏快'),
  otome('乙女向', '甜、黏、关系推进明确，情绪外露'),
  mystery('悬疑本', '信息逐层揭示、基调不安、留白多'),
  daily('日常向', '轻松治愈、单场景、幽默吐槽');

  const StrategyPreset(this.label, this.description);
  final String label;
  final String description;
}

class PromptStrategy {
  const PromptStrategy({
    // —— v1 三组（保留） ——
    required this.advance,
    required this.immersion,
    required this.length,
    this.customMinChars,
    this.customMaxChars,
    // —— v2 视角与叙述 ——
    this.pov = PovStrategy.second,
    this.dialogueRatio = 50,
    this.emotionTone = EmotionTone.warm,
    this.emotionIntensity = 3,
    this.tensionCurve = TensionCurve.rising,
    this.relationshipMode = RelationshipMode.slowburn,
    this.relationshipStepEvery = 10,
    this.relationshipStage = 0,
    this.relationshipLocked = false,
    // —— 硬约束 ——
    this.bannedWords = const <String>[],
    this.catchphrases = const <String>[],
    this.fixedAddressName = '',
    this.noUserAgency = true,
    // —— 描写与节奏 ——
    this.senseVisual = 3,
    this.senseAudio = 2,
    this.senseTouch = 1,
    this.senseSmell = 0,
    this.senseInteroception = 0,
    this.senseAmbient = 1,
    this.pacing = PacingStrategy.singleScene,
    this.reveal = RevealStrategy.layered,
    this.revealMaxPerTurn = 1,
    this.agency = AgencyStrategy.rotate,
    // —— 一致性锚点 ——
    this.anchorTraits = const <String>[],
    this.anchorVoiceSample = '',
    this.anchorSelfCheck = false,
    // —— 排版格式 ——
    this.formatActionItalic = true,
    this.formatQuoteDialogue = true,
    this.formatMaxParagraphs = 5,
    this.formatMarkdown = false,
    // —— 内容强度 ——
    this.intensityConflict = 2,
    this.intensityViolence = 1,
    this.intensityHorror = 1,
    this.intensityIntimacy = 2,
    this.sampling = SamplingPreset.vivid,
    // —— 长篇骨架 ——
    this.structure = NarrativeStructure.threeAct,
    this.structureAct = 1,
    this.structureGoal = '',
    this.conflictPrimary = ConflictType.interpersonal,
    this.conflictSecondary = ConflictType.inner,
    // —— 语言与语境 ——
    this.sentenceLength = 20,
    this.metaphorPerParagraph = 1,
    this.addressMode = AddressMode.fixed,
    this.addressValue = '',
    this.humorLevel = 2,
    this.era = EraSetting.modern,
    this.ambientEnabled = false,
    this.ambientTime = '',
    this.ambientWeather = '',
    this.motifName = '',
    this.motifEveryN = 3,
    this.userExpandLevel = 0,
    this.closureHook = true,
    this.closureDigestEvery = 5,
    this.endingStyle = EndingStyle.open,
    this.npcMax = 3,
    this.aiPlaysNpc = true,
    this.preset,
  });

  factory PromptStrategy.defaults() => const PromptStrategy(
        advance: AdvanceStrategy.forced,
        immersion: ImmersionStrategy.restrained,
        length: LengthStrategy.strict,
      );

  // —— v1 三组 ——
  final AdvanceStrategy advance;
  final ImmersionStrategy immersion;
  final LengthStrategy length;
  final int? customMinChars;
  final int? customMaxChars;

  // —— v2 ——
  final PovStrategy pov;
  final int dialogueRatio;
  final EmotionTone emotionTone;
  final int emotionIntensity;
  final TensionCurve tensionCurve;
  final RelationshipMode relationshipMode;
  final int relationshipStepEvery;
  final int relationshipStage;
  final bool relationshipLocked;
  final List<String> bannedWords;
  final List<String> catchphrases;
  final String fixedAddressName;
  final bool noUserAgency;
  final int senseVisual;
  final int senseAudio;
  final int senseTouch;
  final int senseSmell;
  final int senseInteroception;
  final int senseAmbient;
  final PacingStrategy pacing;
  final RevealStrategy reveal;
  final int revealMaxPerTurn;
  final AgencyStrategy agency;
  final List<String> anchorTraits;
  final String anchorVoiceSample;
  final bool anchorSelfCheck;
  final bool formatActionItalic;
  final bool formatQuoteDialogue;
  final int formatMaxParagraphs;
  final bool formatMarkdown;
  final int intensityConflict;
  final int intensityViolence;
  final int intensityHorror;
  final int intensityIntimacy;
  final SamplingPreset sampling;
  final NarrativeStructure structure;
  final int structureAct;
  final String structureGoal;
  final ConflictType conflictPrimary;
  final ConflictType conflictSecondary;
  final int sentenceLength;
  final int metaphorPerParagraph;
  final AddressMode addressMode;
  final String addressValue;
  final int humorLevel;
  final EraSetting era;
  final bool ambientEnabled;
  final String ambientTime;
  final String ambientWeather;
  final String motifName;
  final int motifEveryN;
  final int userExpandLevel;
  final bool closureHook;
  final int closureDigestEvery;
  final EndingStyle endingStyle;
  final int npcMax;
  final bool aiPlaysNpc;

  /// 最近一次套用的预设（只用于界面上打勾，不影响拼装）。
  final StrategyPreset? preset;

  /// 感官权重总和（>10 时界面提示"会写得很乱"）。
  int get senseTotal =>
      senseVisual + senseAudio + senseTouch + senseSmell + senseInteroception + senseAmbient;

  /// 「极简」字数下对白占比需要压下来，否则一句话占满整轮。
  int get effectiveDialogueRatio {
    if (length == LengthStrategy.tiny) return dialogueRatio.clamp(0, 60);
    return dialogueRatio.clamp(0, 100);
  }

  /// 跟随对手视角天然慢，此时强制推进要降级为慢热。
  AdvanceStrategy get effectiveAdvance {
    if (pov == PovStrategy.followOther && advance == AdvanceStrategy.forced) {
      return AdvanceStrategy.slow;
    }
    return advance;
  }

  PromptStrategy copyWith({
    AdvanceStrategy? advance,
    ImmersionStrategy? immersion,
    LengthStrategy? length,
    int? customMinChars,
    int? customMaxChars,
    PovStrategy? pov,
    int? dialogueRatio,
    EmotionTone? emotionTone,
    int? emotionIntensity,
    TensionCurve? tensionCurve,
    RelationshipMode? relationshipMode,
    int? relationshipStepEvery,
    int? relationshipStage,
    bool? relationshipLocked,
    List<String>? bannedWords,
    List<String>? catchphrases,
    String? fixedAddressName,
    bool? noUserAgency,
    int? senseVisual,
    int? senseAudio,
    int? senseTouch,
    int? senseSmell,
    int? senseInteroception,
    int? senseAmbient,
    PacingStrategy? pacing,
    RevealStrategy? reveal,
    int? revealMaxPerTurn,
    AgencyStrategy? agency,
    List<String>? anchorTraits,
    String? anchorVoiceSample,
    bool? anchorSelfCheck,
    bool? formatActionItalic,
    bool? formatQuoteDialogue,
    int? formatMaxParagraphs,
    bool? formatMarkdown,
    int? intensityConflict,
    int? intensityViolence,
    int? intensityHorror,
    int? intensityIntimacy,
    SamplingPreset? sampling,
    NarrativeStructure? structure,
    int? structureAct,
    String? structureGoal,
    ConflictType? conflictPrimary,
    ConflictType? conflictSecondary,
    int? sentenceLength,
    int? metaphorPerParagraph,
    AddressMode? addressMode,
    String? addressValue,
    int? humorLevel,
    EraSetting? era,
    bool? ambientEnabled,
    String? ambientTime,
    String? ambientWeather,
    String? motifName,
    int? motifEveryN,
    int? userExpandLevel,
    bool? closureHook,
    int? closureDigestEvery,
    EndingStyle? endingStyle,
    int? npcMax,
    bool? aiPlaysNpc,
    StrategyPreset? preset,
    bool clearPreset = false,
  }) {
    return PromptStrategy(
      advance: advance ?? this.advance,
      immersion: immersion ?? this.immersion,
      length: length ?? this.length,
      customMinChars: customMinChars ?? this.customMinChars,
      customMaxChars: customMaxChars ?? this.customMaxChars,
      pov: pov ?? this.pov,
      dialogueRatio: dialogueRatio ?? this.dialogueRatio,
      emotionTone: emotionTone ?? this.emotionTone,
      emotionIntensity: emotionIntensity ?? this.emotionIntensity,
      tensionCurve: tensionCurve ?? this.tensionCurve,
      relationshipMode: relationshipMode ?? this.relationshipMode,
      relationshipStepEvery: relationshipStepEvery ?? this.relationshipStepEvery,
      relationshipStage: relationshipStage ?? this.relationshipStage,
      relationshipLocked: relationshipLocked ?? this.relationshipLocked,
      bannedWords: bannedWords ?? this.bannedWords,
      catchphrases: catchphrases ?? this.catchphrases,
      fixedAddressName: fixedAddressName ?? this.fixedAddressName,
      noUserAgency: noUserAgency ?? this.noUserAgency,
      senseVisual: senseVisual ?? this.senseVisual,
      senseAudio: senseAudio ?? this.senseAudio,
      senseTouch: senseTouch ?? this.senseTouch,
      senseSmell: senseSmell ?? this.senseSmell,
      senseInteroception: senseInteroception ?? this.senseInteroception,
      senseAmbient: senseAmbient ?? this.senseAmbient,
      pacing: pacing ?? this.pacing,
      reveal: reveal ?? this.reveal,
      revealMaxPerTurn: revealMaxPerTurn ?? this.revealMaxPerTurn,
      agency: agency ?? this.agency,
      anchorTraits: anchorTraits ?? this.anchorTraits,
      anchorVoiceSample: anchorVoiceSample ?? this.anchorVoiceSample,
      anchorSelfCheck: anchorSelfCheck ?? this.anchorSelfCheck,
      formatActionItalic: formatActionItalic ?? this.formatActionItalic,
      formatQuoteDialogue: formatQuoteDialogue ?? this.formatQuoteDialogue,
      formatMaxParagraphs: formatMaxParagraphs ?? this.formatMaxParagraphs,
      formatMarkdown: formatMarkdown ?? this.formatMarkdown,
      intensityConflict: intensityConflict ?? this.intensityConflict,
      intensityViolence: intensityViolence ?? this.intensityViolence,
      intensityHorror: intensityHorror ?? this.intensityHorror,
      intensityIntimacy: intensityIntimacy ?? this.intensityIntimacy,
      sampling: sampling ?? this.sampling,
      structure: structure ?? this.structure,
      structureAct: structureAct ?? this.structureAct,
      structureGoal: structureGoal ?? this.structureGoal,
      conflictPrimary: conflictPrimary ?? this.conflictPrimary,
      conflictSecondary: conflictSecondary ?? this.conflictSecondary,
      sentenceLength: sentenceLength ?? this.sentenceLength,
      metaphorPerParagraph: metaphorPerParagraph ?? this.metaphorPerParagraph,
      addressMode: addressMode ?? this.addressMode,
      addressValue: addressValue ?? this.addressValue,
      humorLevel: humorLevel ?? this.humorLevel,
      era: era ?? this.era,
      ambientEnabled: ambientEnabled ?? this.ambientEnabled,
      ambientTime: ambientTime ?? this.ambientTime,
      ambientWeather: ambientWeather ?? this.ambientWeather,
      motifName: motifName ?? this.motifName,
      motifEveryN: motifEveryN ?? this.motifEveryN,
      userExpandLevel: userExpandLevel ?? this.userExpandLevel,
      closureHook: closureHook ?? this.closureHook,
      closureDigestEvery: closureDigestEvery ?? this.closureDigestEvery,
      endingStyle: endingStyle ?? this.endingStyle,
      npcMax: npcMax ?? this.npcMax,
      aiPlaysNpc: aiPlaysNpc ?? this.aiPlaysNpc,
      preset: clearPreset ? null : (preset ?? this.preset),
    );
  }

  /// 套用预设胶囊：按预设把二十余组一次性配好，再打上勾。
  PromptStrategy applyPreset(StrategyPreset p) {
    switch (p) {
      case StrategyPreset.cinematic:
        return copyWith(
          preset: p,
          advance: AdvanceStrategy.slow,
          immersion: ImmersionStrategy.cinematic,
          length: LengthStrategy.unlimited,
          pov: PovStrategy.thirdLimited,
          dialogueRatio: 40,
          emotionTone: EmotionTone.distant,
          emotionIntensity: 2,
          tensionCurve: TensionCurve.rising,
          relationshipMode: RelationshipMode.slowburn,
          senseVisual: 3,
          senseAudio: 2,
          senseTouch: 1,
          senseSmell: 1,
          senseInteroception: 1,
          senseAmbient: 2,
          pacing: PacingStrategy.singleScene,
          formatActionItalic: true,
          formatMaxParagraphs: 4,
          sentenceLength: 16,
          metaphorPerParagraph: 2,
          humorLevel: 1,
          era: EraSetting.modern,
        );
      case StrategyPreset.webnovel:
        return copyWith(
          preset: p,
          advance: AdvanceStrategy.forced,
          immersion: ImmersionStrategy.strong,
          length: LengthStrategy.medium,
          pov: PovStrategy.second,
          dialogueRatio: 65,
          emotionTone: EmotionTone.danger,
          emotionIntensity: 4,
          tensionCurve: TensionCurve.sawtooth,
          relationshipMode: RelationshipMode.fast,
          agency: AgencyStrategy.aiDriven,
          pacing: PacingStrategy.timeMoves,
          reveal: RevealStrategy.all,
          sentenceLength: 14,
          metaphorPerParagraph: 1,
          humorLevel: 3,
          intensityConflict: 3,
        );
      case StrategyPreset.otome:
        return copyWith(
          preset: p,
          advance: AdvanceStrategy.forced,
          immersion: ImmersionStrategy.strong,
          length: LengthStrategy.medium,
          pov: PovStrategy.second,
          dialogueRatio: 60,
          emotionTone: EmotionTone.sweet,
          emotionIntensity: 4,
          tensionCurve: TensionCurve.rising,
          relationshipMode: RelationshipMode.slowburn,
          relationshipStepEvery: 6,
          senseTouch: 2,
          senseInteroception: 2,
          addressMode: AddressMode.relationship,
          humorLevel: 2,
          intensityIntimacy: 3,
        );
      case StrategyPreset.mystery:
        return copyWith(
          preset: p,
          advance: AdvanceStrategy.slow,
          immersion: ImmersionStrategy.cinematic,
          length: LengthStrategy.medium,
          pov: PovStrategy.thirdLimited,
          dialogueRatio: 40,
          emotionTone: EmotionTone.suspense,
          emotionIntensity: 4,
          tensionCurve: TensionCurve.suspended,
          reveal: RevealStrategy.layered,
          revealMaxPerTurn: 1,
          pacing: PacingStrategy.singleScene,
          senseAudio: 3,
          senseAmbient: 2,
          ambientEnabled: true,
          sentenceLength: 18,
          humorLevel: 0,
          intensityHorror: 2,
        );
      case StrategyPreset.daily:
        return copyWith(
          preset: p,
          advance: AdvanceStrategy.free,
          immersion: ImmersionStrategy.restrained,
          length: LengthStrategy.strict,
          pov: PovStrategy.second,
          dialogueRatio: 70,
          emotionTone: EmotionTone.warm,
          emotionIntensity: 2,
          tensionCurve: TensionCurve.rising,
          relationshipMode: RelationshipMode.natural,
          pacing: PacingStrategy.singleScene,
          humorLevel: 4,
          senseVisual: 2,
          senseAudio: 2,
          senseTouch: 1,
          intensityConflict: 1,
        );
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': 2,
      // v1
      'advance': advance.name,
      'immersion': immersion.name,
      'length': length.name,
      if (customMinChars != null) 'customMinChars': customMinChars,
      if (customMaxChars != null) 'customMaxChars': customMaxChars,
      // v2
      'pov': pov.name,
      'dialogueRatio': dialogueRatio,
      'emotionTone': emotionTone.name,
      'emotionIntensity': emotionIntensity,
      'tensionCurve': tensionCurve.name,
      'relationshipMode': relationshipMode.name,
      'relationshipStepEvery': relationshipStepEvery,
      'relationshipStage': relationshipStage,
      'relationshipLocked': relationshipLocked,
      'bannedWords': bannedWords,
      'catchphrases': catchphrases,
      'fixedAddressName': fixedAddressName,
      'noUserAgency': noUserAgency,
      'senseVisual': senseVisual,
      'senseAudio': senseAudio,
      'senseTouch': senseTouch,
      'senseSmell': senseSmell,
      'senseInteroception': senseInteroception,
      'senseAmbient': senseAmbient,
      'pacing': pacing.name,
      'reveal': reveal.name,
      'revealMaxPerTurn': revealMaxPerTurn,
      'agency': agency.name,
      'anchorTraits': anchorTraits,
      'anchorVoiceSample': anchorVoiceSample,
      'anchorSelfCheck': anchorSelfCheck,
      'formatActionItalic': formatActionItalic,
      'formatQuoteDialogue': formatQuoteDialogue,
      'formatMaxParagraphs': formatMaxParagraphs,
      'formatMarkdown': formatMarkdown,
      'intensityConflict': intensityConflict,
      'intensityViolence': intensityViolence,
      'intensityHorror': intensityHorror,
      'intensityIntimacy': intensityIntimacy,
      'sampling': sampling.name,
      'structure': structure.name,
      'structureAct': structureAct,
      'structureGoal': structureGoal,
      'conflictPrimary': conflictPrimary.name,
      'conflictSecondary': conflictSecondary.name,
      'sentenceLength': sentenceLength,
      'metaphorPerParagraph': metaphorPerParagraph,
      'addressMode': addressMode.name,
      'addressValue': addressValue,
      'humorLevel': humorLevel,
      'era': era.name,
      'ambientEnabled': ambientEnabled,
      'ambientTime': ambientTime,
      'ambientWeather': ambientWeather,
      'motifName': motifName,
      'motifEveryN': motifEveryN,
      'userExpandLevel': userExpandLevel,
      'closureHook': closureHook,
      'closureDigestEvery': closureDigestEvery,
      'endingStyle': endingStyle.name,
      'npcMax': npcMax,
      'aiPlaysNpc': aiPlaysNpc,
      if (preset != null) 'preset': preset!.name,
    };
  }

  factory PromptStrategy.fromJson(Map<String, dynamic> json) {
    final PromptStrategy d = PromptStrategy.defaults();
    T enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
      if (raw is String) {
        for (final T v in values) {
          if (v.name == raw) return v;
        }
      }
      return fallback;
    }

    int intOf(Object? raw, int fallback) => raw is int ? raw : (raw is num ? raw.toInt() : fallback);
    bool boolOf(Object? raw, bool fallback) => raw is bool ? raw : fallback;
    String strOf(Object? raw, String fallback) => raw is String ? raw : fallback;
    List<String> listOf(Object? raw) {
      if (raw is List) {
        return raw.whereType<String>().map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
      }
      return const <String>[];
    }

    return PromptStrategy(
      advance: enumOf(AdvanceStrategy.values, json['advance'], d.advance),
      immersion: enumOf(ImmersionStrategy.values, json['immersion'], d.immersion),
      length: enumOf(LengthStrategy.values, json['length'], d.length),
      customMinChars: json['customMinChars'] is int ? json['customMinChars'] as int : null,
      customMaxChars: json['customMaxChars'] is int ? json['customMaxChars'] as int : null,
      pov: enumOf(PovStrategy.values, json['pov'], d.pov),
      dialogueRatio: intOf(json['dialogueRatio'], d.dialogueRatio),
      emotionTone: enumOf(EmotionTone.values, json['emotionTone'], d.emotionTone),
      emotionIntensity: intOf(json['emotionIntensity'], d.emotionIntensity),
      tensionCurve: enumOf(TensionCurve.values, json['tensionCurve'], d.tensionCurve),
      relationshipMode: enumOf(RelationshipMode.values, json['relationshipMode'], d.relationshipMode),
      relationshipStepEvery: intOf(json['relationshipStepEvery'], d.relationshipStepEvery),
      relationshipStage: intOf(json['relationshipStage'], d.relationshipStage),
      relationshipLocked: boolOf(json['relationshipLocked'], d.relationshipLocked),
      bannedWords: listOf(json['bannedWords']),
      catchphrases: listOf(json['catchphrases']),
      fixedAddressName: strOf(json['fixedAddressName'], d.fixedAddressName),
      noUserAgency: boolOf(json['noUserAgency'], d.noUserAgency),
      senseVisual: intOf(json['senseVisual'], d.senseVisual),
      senseAudio: intOf(json['senseAudio'], d.senseAudio),
      senseTouch: intOf(json['senseTouch'], d.senseTouch),
      senseSmell: intOf(json['senseSmell'], d.senseSmell),
      senseInteroception: intOf(json['senseInteroception'], d.senseInteroception),
      senseAmbient: intOf(json['senseAmbient'], d.senseAmbient),
      pacing: enumOf(PacingStrategy.values, json['pacing'], d.pacing),
      reveal: enumOf(RevealStrategy.values, json['reveal'], d.reveal),
      revealMaxPerTurn: intOf(json['revealMaxPerTurn'], d.revealMaxPerTurn),
      agency: enumOf(AgencyStrategy.values, json['agency'], d.agency),
      anchorTraits: listOf(json['anchorTraits']),
      anchorVoiceSample: strOf(json['anchorVoiceSample'], d.anchorVoiceSample),
      anchorSelfCheck: boolOf(json['anchorSelfCheck'], d.anchorSelfCheck),
      formatActionItalic: boolOf(json['formatActionItalic'], d.formatActionItalic),
      formatQuoteDialogue: boolOf(json['formatQuoteDialogue'], d.formatQuoteDialogue),
      formatMaxParagraphs: intOf(json['formatMaxParagraphs'], d.formatMaxParagraphs),
      formatMarkdown: boolOf(json['formatMarkdown'], d.formatMarkdown),
      intensityConflict: intOf(json['intensityConflict'], d.intensityConflict),
      intensityViolence: intOf(json['intensityViolence'], d.intensityViolence),
      intensityHorror: intOf(json['intensityHorror'], d.intensityHorror),
      intensityIntimacy: intOf(json['intensityIntimacy'], d.intensityIntimacy),
      sampling: enumOf(SamplingPreset.values, json['sampling'], d.sampling),
      structure: enumOf(NarrativeStructure.values, json['structure'], d.structure),
      structureAct: intOf(json['structureAct'], d.structureAct),
      structureGoal: strOf(json['structureGoal'], d.structureGoal),
      conflictPrimary: enumOf(ConflictType.values, json['conflictPrimary'], d.conflictPrimary),
      conflictSecondary: enumOf(ConflictType.values, json['conflictSecondary'], d.conflictSecondary),
      sentenceLength: intOf(json['sentenceLength'], d.sentenceLength),
      metaphorPerParagraph: intOf(json['metaphorPerParagraph'], d.metaphorPerParagraph),
      addressMode: enumOf(AddressMode.values, json['addressMode'], d.addressMode),
      addressValue: strOf(json['addressValue'], d.addressValue),
      humorLevel: intOf(json['humorLevel'], d.humorLevel),
      era: enumOf(EraSetting.values, json['era'], d.era),
      ambientEnabled: boolOf(json['ambientEnabled'], d.ambientEnabled),
      ambientTime: strOf(json['ambientTime'], d.ambientTime),
      ambientWeather: strOf(json['ambientWeather'], d.ambientWeather),
      motifName: strOf(json['motifName'], d.motifName),
      motifEveryN: intOf(json['motifEveryN'], d.motifEveryN),
      userExpandLevel: intOf(json['userExpandLevel'], d.userExpandLevel),
      closureHook: boolOf(json['closureHook'], d.closureHook),
      closureDigestEvery: intOf(json['closureDigestEvery'], d.closureDigestEvery),
      endingStyle: enumOf(EndingStyle.values, json['endingStyle'], d.endingStyle),
      npcMax: intOf(json['npcMax'], d.npcMax),
      aiPlaysNpc: boolOf(json['aiPlaysNpc'], d.aiPlaysNpc),
      preset: json['preset'] is String
          ? enumOf(StrategyPreset.values, json['preset'], StrategyPreset.daily)
          : null,
    );
  }
}

/// 各枚举的中文标签（界面与说明共用）。
const Map<PovStrategy, String> kPovLabels = <PovStrategy, String>{
  PovStrategy.second: '第二人称「你」',
  PovStrategy.first: '第一人称「我」',
  PovStrategy.thirdLimited: '第三人称·限知',
  PovStrategy.thirdOmniscient: '第三人称·全知',
  PovStrategy.followOther: '跟随对手角色',
  PovStrategy.observer: '旁观者',
};

const Map<TensionCurve, String> kTensionLabels = <TensionCurve, String>{
  TensionCurve.singlePeak: '单峰爆发',
  TensionCurve.doublePeak: '双峰波谷',
  TensionCurve.rising: '缓升不落',
  TensionCurve.sawtooth: '锯齿高频',
  TensionCurve.suspended: '悬置（憋着）',
};

const Map<RelationshipMode, String> kRelationshipLabels = <RelationshipMode, String>{
  RelationshipMode.frozen: '冻结',
  RelationshipMode.slowburn: '慢热',
  RelationshipMode.natural: '自然',
  RelationshipMode.fast: '快进',
  RelationshipMode.userOnly: '仅用户解锁',
};

const Map<PacingStrategy, String> kPacingLabels = <PacingStrategy, String>{
  PacingStrategy.singleScene: '单场景连戏',
  PacingStrategy.jumpScene: '允许跳场',
  PacingStrategy.timeJump: '允许时间跳跃',
  PacingStrategy.montage: '蒙太奇剪辑',
  PacingStrategy.timeMoves: '每轮推进时间',
};

const Map<RevealStrategy, String> kRevealLabels = <RevealStrategy, String>{
  RevealStrategy.layered: '逐层递进',
  RevealStrategy.all: '一次给足',
  RevealStrategy.blank: '故意留白',
  RevealStrategy.unreliable: '不可靠叙述',
  RevealStrategy.limited: '视角受限',
};

const Map<AgencyStrategy, String> kAgencyLabels = <AgencyStrategy, String>{
  AgencyStrategy.aiDriven: 'AI 主导',
  AgencyStrategy.respondOnly: '只回应',
  AgencyStrategy.rotate: '轮替',
  AgencyStrategy.userDriven: '用户主导',
};

const Map<EmotionTone, String> kEmotionLabels = <EmotionTone, String>{
  EmotionTone.distant: '疏离克制',
  EmotionTone.warm: '温和治愈',
  EmotionTone.danger: '危险压迫',
  EmotionTone.blackHumor: '黑色幽默',
  EmotionTone.suspense: '悬疑不安',
  EmotionTone.sweet: '甜腻黏稠',
};

const Map<NarrativeStructure, String> kNarrativeLabels = <NarrativeStructure, String>{
  NarrativeStructure.threeAct: '三幕',
  NarrativeStructure.chapters: '章回',
  NarrativeStructure.slice: '日常切片',
  NarrativeStructure.loop: '循环',
  NarrativeStructure.epistolary: '书信体',
};

const Map<ConflictType, String> kConflictLabels = <ConflictType, String>{
  ConflictType.interpersonal: '人际',
  ConflictType.environment: '环境',
  ConflictType.inner: '内心',
  ConflictType.timePressure: '时间压力',
  ConflictType.institution: '制度',
  ConflictType.information: '信息差',
};

const Map<EraSetting, String> kEraLabels = <EraSetting, String>{
  EraSetting.modern: '现代都市',
  EraSetting.nearFuture: '近未来',
  EraSetting.fantasy: '架空',
  EraSetting.academy: '学院',
  EraSetting.workplace: '职场',
  EraSetting.wilderness: '荒野',
};

const Map<AddressMode, String> kAddressLabels = <AddressMode, String>{
  AddressMode.fixed: '固定称呼',
  AddressMode.relationship: '随关系变化',
  AddressMode.emotion: '随情绪变化',
  AddressMode.custom: '用户指定',
};

const Map<EndingStyle, String> kEndingLabels = <EndingStyle, String>{
  EndingStyle.open: '开放',
  EndingStyle.closed: '闭合',
  EndingStyle.loop: '循环',
};

const Map<SamplingPreset, String> kSamplingLabels = <SamplingPreset, String>{
  SamplingPreset.strict: '严谨',
  SamplingPreset.standard: '标准',
  SamplingPreset.vivid: '生动',
  SamplingPreset.wild: '放飞',
};

/// 关系阶段（0-4）：界面上的阶段条与提示语共用。
const List<String> kRelationshipStages = <String>['陌生', '试探', '靠近', '交心', '绑定'];
