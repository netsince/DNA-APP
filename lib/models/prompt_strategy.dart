enum AdvanceStrategy {
  forced,
  free,
}

enum ImmersionStrategy {
  restrained,
  strong,
}

enum LengthStrategy {
  strict,
  medium,
  unlimited,
  custom,
}

/// 内容尺度档位：0 表示不额外约束（默认，保持既有行为）。
///
/// 只影响提示词里的「尺度说明」，不做内容过滤 —— 由用户在设置里自己选。
enum IntensityLevel {
  unrestricted(0, '不限'),
  mild(1, '轻微'),
  moderate(2, '适中'),
  marked(3, '明显'),
  strong(4, '强烈'),
  extreme(5, '极端');

  const IntensityLevel(this.value, this.label);

  final int value;
  final String label;

  static IntensityLevel fromValue(int? v) {
    for (final IntensityLevel level in IntensityLevel.values) {
      if (level.value == (v ?? 0)) return level;
    }
    return IntensityLevel.unrestricted;
  }
}

class PromptStrategy {
  const PromptStrategy({
    required this.advance,
    required this.immersion,
    required this.length,
    this.customMinChars,
    this.customMaxChars,
    this.conflictIntensity = IntensityLevel.unrestricted,
    this.violenceIntensity = IntensityLevel.unrestricted,
    this.horrorIntensity = IntensityLevel.unrestricted,
    this.intimacyIntensity = IntensityLevel.unrestricted,
    this.bannedWords = const <String>[],
    this.formatActionItalic = false,
    this.formatQuoteDialogue = false,
    this.formatMaxParagraphs = 0,
    this.formatMarkdown = false,
    this.details = const StrategyDetails(),
  });

  factory PromptStrategy.defaults() {
    return const PromptStrategy(
      advance: AdvanceStrategy.forced,
      immersion: ImmersionStrategy.restrained,
      length: LengthStrategy.strict,
      customMinChars: null,
      customMaxChars: null,
    );
  }

  final AdvanceStrategy advance;
  final ImmersionStrategy immersion;
  final LengthStrategy length;

  /// 自定义字数的下限（长度策略为 custom 时生效），单位：字。
  final int? customMinChars;

  /// 自定义字数的上限（长度策略为 custom 时生效），单位：字。
  final int? customMaxChars;

  // ---- 内容尺度（全局）：用户的接受度，不随角色变化 ----
  final IntensityLevel conflictIntensity;
  final IntensityLevel violenceIntensity;
  final IntensityLevel horrorIntensity;
  final IntensityLevel intimacyIntensity;

  // ---- 用词限制（全局）：用户不想看到的表达 ----
  final List<String> bannedWords;

  // ---- 排版格式（全局）：阅读偏好，不改变 AI 的写法 ----
  /// 动作/旁白是否用斜体呈现。
  final bool formatActionItalic;

  /// 台词是否用引号包裹。
  final bool formatQuoteDialogue;

  /// 单条回复的最大段落数；0 表示不限制。
  final int formatMaxParagraphs;

  /// 是否允许 Markdown 语法。
  final bool formatMarkdown;

  /// 三层结构的细节项；空表示全部未设置（不写进提示词）。
  final StrategyDetails details;

  bool get hasIntensityLimit =>
      conflictIntensity != IntensityLevel.unrestricted ||
      violenceIntensity != IntensityLevel.unrestricted ||
      horrorIntensity != IntensityLevel.unrestricted ||
      intimacyIntensity != IntensityLevel.unrestricted;

  bool get hasFormatRule =>
      formatActionItalic ||
      formatQuoteDialogue ||
      formatMaxParagraphs > 0 ||
      formatMarkdown;

  PromptStrategy copyWith({
    AdvanceStrategy? advance,
    ImmersionStrategy? immersion,
    LengthStrategy? length,
    int? customMinChars,
    int? customMaxChars,
    IntensityLevel? conflictIntensity,
    IntensityLevel? violenceIntensity,
    IntensityLevel? horrorIntensity,
    IntensityLevel? intimacyIntensity,
    List<String>? bannedWords,
    bool? formatActionItalic,
    bool? formatQuoteDialogue,
    int? formatMaxParagraphs,
    bool? formatMarkdown,
    StrategyDetails? details,
  }) {
    return PromptStrategy(
      advance: advance ?? this.advance,
      immersion: immersion ?? this.immersion,
      length: length ?? this.length,
      customMinChars: customMinChars ?? this.customMinChars,
      customMaxChars: customMaxChars ?? this.customMaxChars,
      conflictIntensity: conflictIntensity ?? this.conflictIntensity,
      violenceIntensity: violenceIntensity ?? this.violenceIntensity,
      horrorIntensity: horrorIntensity ?? this.horrorIntensity,
      intimacyIntensity: intimacyIntensity ?? this.intimacyIntensity,
      bannedWords: bannedWords ?? this.bannedWords,
      formatActionItalic: formatActionItalic ?? this.formatActionItalic,
      formatQuoteDialogue: formatQuoteDialogue ?? this.formatQuoteDialogue,
      formatMaxParagraphs: formatMaxParagraphs ?? this.formatMaxParagraphs,
      formatMarkdown: formatMarkdown ?? this.formatMarkdown,
      details: details ?? this.details,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'advance': advance.name,
      'immersion': immersion.name,
      'length': length.name,
      if (customMinChars != null) 'customMinChars': customMinChars,
      if (customMaxChars != null) 'customMaxChars': customMaxChars,
      // 新字段只在非默认值时落盘：老版本读到的仍是老形状。
      if (conflictIntensity != IntensityLevel.unrestricted)
        'conflictIntensity': conflictIntensity.value,
      if (violenceIntensity != IntensityLevel.unrestricted)
        'violenceIntensity': violenceIntensity.value,
      if (horrorIntensity != IntensityLevel.unrestricted)
        'horrorIntensity': horrorIntensity.value,
      if (intimacyIntensity != IntensityLevel.unrestricted)
        'intimacyIntensity': intimacyIntensity.value,
      if (bannedWords.isNotEmpty) 'bannedWords': bannedWords,
      if (formatActionItalic) 'formatActionItalic': true,
      if (formatQuoteDialogue) 'formatQuoteDialogue': true,
      if (formatMaxParagraphs > 0) 'formatMaxParagraphs': formatMaxParagraphs,
      if (formatMarkdown) 'formatMarkdown': true,
      if (!details.isEmpty) 'details': details.toJson(),
    };
  }

  factory PromptStrategy.fromJson(Map<String, dynamic> json) {
    return PromptStrategy(
      advance: AdvanceStrategy.values.byName(json['advance'] as String),
      immersion: ImmersionStrategy.values.byName(json['immersion'] as String),
      length: LengthStrategy.values.byName(json['length'] as String),
      customMinChars: json['customMinChars'] as int?,
      customMaxChars: json['customMaxChars'] as int?,
      conflictIntensity:
          IntensityLevel.fromValue(json['conflictIntensity'] as int?),
      violenceIntensity:
          IntensityLevel.fromValue(json['violenceIntensity'] as int?),
      horrorIntensity: IntensityLevel.fromValue(json['horrorIntensity'] as int?),
      intimacyIntensity:
          IntensityLevel.fromValue(json['intimacyIntensity'] as int?),
      bannedWords: (json['bannedWords'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .where((String e) => e.trim().isNotEmpty)
              .toList() ??
          const <String>[],
      formatActionItalic: json['formatActionItalic'] as bool? ?? false,
      formatQuoteDialogue: json['formatQuoteDialogue'] as bool? ?? false,
      formatMaxParagraphs: json['formatMaxParagraphs'] as int? ?? 0,
      formatMarkdown: json['formatMarkdown'] as bool? ?? false,
      details: StrategyDetails.fromJson(
        json['details'] is Map
            ? (json['details'] as Map).cast<String, dynamic>()
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 三层结构的「主轴」与「细项」
//
// 这些字段全部可空：**null 表示未设置**，不写进提示词，行为与升级前一致。
// 同一套字段承担三个角色：
//   全局默认（设置 → 提示词策略 → 高级）
//   角色卡覆盖（角色编辑页 → 对话策略）
//   世界卡覆盖（世界编辑页 → 叙事策略）
// 合并顺序固定为：角色卡 > 世界卡 > 全局。
// ---------------------------------------------------------------------------

/// 叙事视角。
enum Pov {
  first('第一人称'),
  third('第三人称'),
  omniscient('全知');

  const Pov(this.label);

  final String label;
}

/// 叙事结构。
enum NarrativeStructure {
  threeAct('三幕'),
  chapters('章节'),
  slice('切片（单场景）'),
  loop('循环'),
  epistolary('书信 / 记录体');

  const NarrativeStructure(this.label);

  final String label;
}

/// 场景与时序。
enum Pacing {
  scene('场景推进'),
  chronological('顺时序'),
  fragmented('跳跃剪辑');

  const Pacing(this.label);

  final String label;
}

/// 张力曲线形状。
enum TensionCurve {
  rising('逐级递进'),
  wave('起伏交替'),
  flat('平稳克制'),
  spike('短促突刺');

  const TensionCurve(this.label);

  final String label;
}

/// 信息揭示方式。
enum Reveal {
  layered('逐层揭示'),
  all('一次给全'),
  blank('大量留白'),
  unreliable('不可靠叙述'),
  limited('受限视角');

  const Reveal(this.label);

  final String label;
}

/// 冲突来源。
enum ConflictSource {
  interpersonal('人际'),
  inner('内心'),
  environment('环境'),
  institution('制度'),
  supernatural('超自然');

  const ConflictSource(this.label);

  final String label;
}

/// 结局收束方式。
enum EndingStyle {
  open('开放'),
  closed('闭环'),
  loop('回环');

  const EndingStyle(this.label);

  final String label;
}

/// 称呼方式。
enum AddressMode {
  fixed('固定称呼'),
  relationship('随关系变化'),
  emotion('随情绪变化'),
  custom('自定义');

  const AddressMode(this.label);

  final String label;
}

/// 情绪基调。
enum EmotionTone {
  calm('平静'),
  warm('温和'),
  danger('危险'),
  humor('轻快'),
  suspense('悬疑'),
  sweet('甜');

  const EmotionTone(this.label);

  final String label;
}

/// 一层可选的策略细节。
///
/// 全部字段可空；[mergedWith] 用来把「角色卡覆盖」叠到「世界卡覆盖」再叠到
/// 「全局默认」上 —— 高优先级的非空值胜出，空的仍然继承低优先级。
class StrategyDetails {
  const StrategyDetails({
    this.pov,
    this.narrativeStructure,
    this.structureGoal,
    this.pacing,
    this.tensionCurve,
    this.reveal,
    this.revealMaxPerTurn,
    this.conflictPrimary,
    this.conflictSecondary,
    this.endingStyle,
    this.closureHook,
    this.ambientEnabled,
    this.ambientTime,
    this.ambientWeather,
    this.npcMax,
    this.aiPlaysNpc,
    this.emotionTone,
    this.emotionIntensity,
    this.addressMode,
    this.addressValue,
    this.catchphrases,
    this.anchorTraits,
    this.anchorVoiceSample,
    this.sentenceLength,
    this.metaphorPerParagraph,
    this.humorLevel,
    this.dialogueRatio,
    this.motifName,
    this.motifEveryN,
  });

  // ---- 视角与叙事 ----
  final Pov? pov;
  final NarrativeStructure? narrativeStructure;
  final String? structureGoal;
  final Pacing? pacing;
  final TensionCurve? tensionCurve;
  final Reveal? reveal;
  final int? revealMaxPerTurn;

  // ---- 冲突与收束 ----
  final ConflictSource? conflictPrimary;
  final ConflictSource? conflictSecondary;
  final EndingStyle? endingStyle;
  final bool? closureHook;

  // ---- 场景与配角 ----
  final bool? ambientEnabled;
  final String? ambientTime;
  final String? ambientWeather;
  final int? npcMax;
  final bool? aiPlaysNpc;

  // ---- 角色口吻 ----
  final EmotionTone? emotionTone;
  final int? emotionIntensity;
  final AddressMode? addressMode;
  final String? addressValue;
  final List<String>? catchphrases;
  final List<String>? anchorTraits;
  final String? anchorVoiceSample;

  // ---- 文风 ----
  final int? sentenceLength;
  final int? metaphorPerParagraph;
  final int? humorLevel;
  final int? dialogueRatio;

  // ---- 母题 ----
  final String? motifName;
  final int? motifEveryN;

  /// 全部未设置。
  bool get isEmpty =>
      pov == null &&
      narrativeStructure == null &&
      (structureGoal == null || structureGoal!.trim().isEmpty) &&
      pacing == null &&
      tensionCurve == null &&
      reveal == null &&
      revealMaxPerTurn == null &&
      conflictPrimary == null &&
      conflictSecondary == null &&
      endingStyle == null &&
      closureHook == null &&
      ambientEnabled == null &&
      (ambientTime == null || ambientTime!.trim().isEmpty) &&
      (ambientWeather == null || ambientWeather!.trim().isEmpty) &&
      npcMax == null &&
      aiPlaysNpc == null &&
      emotionTone == null &&
      emotionIntensity == null &&
      addressMode == null &&
      (addressValue == null || addressValue!.trim().isEmpty) &&
      (catchphrases == null || catchphrases!.isEmpty) &&
      (anchorTraits == null || anchorTraits!.isEmpty) &&
      (anchorVoiceSample == null || anchorVoiceSample!.trim().isEmpty) &&
      sentenceLength == null &&
      metaphorPerParagraph == null &&
      humorLevel == null &&
      dialogueRatio == null &&
      (motifName == null || motifName!.trim().isEmpty) &&
      motifEveryN == null;

  /// 用 [override] 里非空的项覆盖自己，返回新实例（不改自身）。
  StrategyDetails mergedWith(StrategyDetails? override) {
    if (override == null || override.isEmpty) {
      return this;
    }
    return StrategyDetails(
      pov: override.pov ?? pov,
      narrativeStructure: override.narrativeStructure ?? narrativeStructure,
      structureGoal: override.structureGoal ?? structureGoal,
      pacing: override.pacing ?? pacing,
      tensionCurve: override.tensionCurve ?? tensionCurve,
      reveal: override.reveal ?? reveal,
      revealMaxPerTurn: override.revealMaxPerTurn ?? revealMaxPerTurn,
      conflictPrimary: override.conflictPrimary ?? conflictPrimary,
      conflictSecondary: override.conflictSecondary ?? conflictSecondary,
      endingStyle: override.endingStyle ?? endingStyle,
      closureHook: override.closureHook ?? closureHook,
      ambientEnabled: override.ambientEnabled ?? ambientEnabled,
      ambientTime: override.ambientTime ?? ambientTime,
      ambientWeather: override.ambientWeather ?? ambientWeather,
      npcMax: override.npcMax ?? npcMax,
      aiPlaysNpc: override.aiPlaysNpc ?? aiPlaysNpc,
      emotionTone: override.emotionTone ?? emotionTone,
      emotionIntensity: override.emotionIntensity ?? emotionIntensity,
      addressMode: override.addressMode ?? addressMode,
      addressValue: override.addressValue ?? addressValue,
      catchphrases: override.catchphrases ?? catchphrases,
      anchorTraits: override.anchorTraits ?? anchorTraits,
      anchorVoiceSample: override.anchorVoiceSample ?? anchorVoiceSample,
      sentenceLength: override.sentenceLength ?? sentenceLength,
      metaphorPerParagraph:
          override.metaphorPerParagraph ?? metaphorPerParagraph,
      humorLevel: override.humorLevel ?? humorLevel,
      dialogueRatio: override.dialogueRatio ?? dialogueRatio,
      motifName: override.motifName ?? motifName,
      motifEveryN: override.motifEveryN ?? motifEveryN,
    );
  }


  /// 改单项：**传 null 表示清空**（回到「未设置」），不传则保持原值。
  ///
  /// 用哨兵而不是 `T?` 作默认值，是因为 `pov: null` 在这套语义里
  /// 必须表示「清空」，而普通 copyWith 的 `null` 只能表示「不改」。
  StrategyDetails copyWith({
    Object? pov = _keep,
    Object? narrativeStructure = _keep,
    Object? structureGoal = _keep,
    Object? pacing = _keep,
    Object? tensionCurve = _keep,
    Object? reveal = _keep,
    Object? revealMaxPerTurn = _keep,
    Object? conflictPrimary = _keep,
    Object? conflictSecondary = _keep,
    Object? endingStyle = _keep,
    Object? closureHook = _keep,
    Object? ambientEnabled = _keep,
    Object? ambientTime = _keep,
    Object? ambientWeather = _keep,
    Object? npcMax = _keep,
    Object? aiPlaysNpc = _keep,
    Object? emotionTone = _keep,
    Object? emotionIntensity = _keep,
    Object? addressMode = _keep,
    Object? addressValue = _keep,
    Object? catchphrases = _keep,
    Object? anchorTraits = _keep,
    Object? anchorVoiceSample = _keep,
    Object? sentenceLength = _keep,
    Object? metaphorPerParagraph = _keep,
    Object? humorLevel = _keep,
    Object? dialogueRatio = _keep,
    Object? motifName = _keep,
    Object? motifEveryN = _keep,
  }) {
    return StrategyDetails(
      pov: identical(pov, _keep) ? this.pov : pov as Pov?,
      narrativeStructure: identical(narrativeStructure, _keep) ? this.narrativeStructure : narrativeStructure as NarrativeStructure?,
      structureGoal: identical(structureGoal, _keep) ? this.structureGoal : structureGoal as String?,
      pacing: identical(pacing, _keep) ? this.pacing : pacing as Pacing?,
      tensionCurve: identical(tensionCurve, _keep) ? this.tensionCurve : tensionCurve as TensionCurve?,
      reveal: identical(reveal, _keep) ? this.reveal : reveal as Reveal?,
      revealMaxPerTurn: identical(revealMaxPerTurn, _keep) ? this.revealMaxPerTurn : revealMaxPerTurn as int?,
      conflictPrimary: identical(conflictPrimary, _keep) ? this.conflictPrimary : conflictPrimary as ConflictSource?,
      conflictSecondary: identical(conflictSecondary, _keep) ? this.conflictSecondary : conflictSecondary as ConflictSource?,
      endingStyle: identical(endingStyle, _keep) ? this.endingStyle : endingStyle as EndingStyle?,
      closureHook: identical(closureHook, _keep) ? this.closureHook : closureHook as bool?,
      ambientEnabled: identical(ambientEnabled, _keep) ? this.ambientEnabled : ambientEnabled as bool?,
      ambientTime: identical(ambientTime, _keep) ? this.ambientTime : ambientTime as String?,
      ambientWeather: identical(ambientWeather, _keep) ? this.ambientWeather : ambientWeather as String?,
      npcMax: identical(npcMax, _keep) ? this.npcMax : npcMax as int?,
      aiPlaysNpc: identical(aiPlaysNpc, _keep) ? this.aiPlaysNpc : aiPlaysNpc as bool?,
      emotionTone: identical(emotionTone, _keep) ? this.emotionTone : emotionTone as EmotionTone?,
      emotionIntensity: identical(emotionIntensity, _keep) ? this.emotionIntensity : emotionIntensity as int?,
      addressMode: identical(addressMode, _keep) ? this.addressMode : addressMode as AddressMode?,
      addressValue: identical(addressValue, _keep) ? this.addressValue : addressValue as String?,
      catchphrases: identical(catchphrases, _keep) ? this.catchphrases : catchphrases as List<String>?,
      anchorTraits: identical(anchorTraits, _keep) ? this.anchorTraits : anchorTraits as List<String>?,
      anchorVoiceSample: identical(anchorVoiceSample, _keep) ? this.anchorVoiceSample : anchorVoiceSample as String?,
      sentenceLength: identical(sentenceLength, _keep) ? this.sentenceLength : sentenceLength as int?,
      metaphorPerParagraph: identical(metaphorPerParagraph, _keep) ? this.metaphorPerParagraph : metaphorPerParagraph as int?,
      humorLevel: identical(humorLevel, _keep) ? this.humorLevel : humorLevel as int?,
      dialogueRatio: identical(dialogueRatio, _keep) ? this.dialogueRatio : dialogueRatio as int?,
      motifName: identical(motifName, _keep) ? this.motifName : motifName as String?,
      motifEveryN: identical(motifEveryN, _keep) ? this.motifEveryN : motifEveryN as int?,
    );
  }

  /// 哨兵：区分「没传」与「显式传 null」。
  static const Object _keep = Object();
  /// 只写出非空项 —— 未设置的项不落盘，旧版本读到仍是旧形状。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (pov != null) 'pov': pov!.name,
      if (narrativeStructure != null)
        'narrativeStructure': narrativeStructure!.name,
      if (structureGoal != null && structureGoal!.trim().isNotEmpty)
        'structureGoal': structureGoal,
      if (pacing != null) 'pacing': pacing!.name,
      if (tensionCurve != null) 'tensionCurve': tensionCurve!.name,
      if (reveal != null) 'reveal': reveal!.name,
      if (revealMaxPerTurn != null) 'revealMaxPerTurn': revealMaxPerTurn,
      if (conflictPrimary != null) 'conflictPrimary': conflictPrimary!.name,
      if (conflictSecondary != null)
        'conflictSecondary': conflictSecondary!.name,
      if (endingStyle != null) 'endingStyle': endingStyle!.name,
      if (closureHook != null) 'closureHook': closureHook,
      if (ambientEnabled != null) 'ambientEnabled': ambientEnabled,
      if (ambientTime != null && ambientTime!.trim().isNotEmpty)
        'ambientTime': ambientTime,
      if (ambientWeather != null && ambientWeather!.trim().isNotEmpty)
        'ambientWeather': ambientWeather,
      if (npcMax != null) 'npcMax': npcMax,
      if (aiPlaysNpc != null) 'aiPlaysNpc': aiPlaysNpc,
      if (emotionTone != null) 'emotionTone': emotionTone!.name,
      if (emotionIntensity != null) 'emotionIntensity': emotionIntensity,
      if (addressMode != null) 'addressMode': addressMode!.name,
      if (addressValue != null && addressValue!.trim().isNotEmpty)
        'addressValue': addressValue,
      if (catchphrases != null && catchphrases!.isNotEmpty)
        'catchphrases': catchphrases,
      if (anchorTraits != null && anchorTraits!.isNotEmpty)
        'anchorTraits': anchorTraits,
      if (anchorVoiceSample != null && anchorVoiceSample!.trim().isNotEmpty)
        'anchorVoiceSample': anchorVoiceSample,
      if (sentenceLength != null) 'sentenceLength': sentenceLength,
      if (metaphorPerParagraph != null)
        'metaphorPerParagraph': metaphorPerParagraph,
      if (humorLevel != null) 'humorLevel': humorLevel,
      if (dialogueRatio != null) 'dialogueRatio': dialogueRatio,
      if (motifName != null && motifName!.trim().isNotEmpty)
        'motifName': motifName,
      if (motifEveryN != null) 'motifEveryN': motifEveryN,
    };
  }

  /// 解析一层覆盖：**没有内容就返回 null**，而不是空对象。
  ///
  /// 「未设置」在语义上是 null；返回空对象会让 `copyWith`、脏检查、序列化
  /// 多出一个「看起来设了其实什么都没设」的中间态。
  static StrategyDetails? fromJsonOrNull(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    final StrategyDetails parsed = StrategyDetails.fromJson(json);
    return parsed.isEmpty ? null : parsed;
  }

  /// 容错解析：认不出的枚举名一律当作未设置，不抛异常。
  factory StrategyDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const StrategyDetails();
    }
    return StrategyDetails(
      pov: _byName(Pov.values, json['pov']),
      narrativeStructure:
          _byName(NarrativeStructure.values, json['narrativeStructure']),
      structureGoal: _asString(json['structureGoal']),
      pacing: _byName(Pacing.values, json['pacing']),
      tensionCurve: _byName(TensionCurve.values, json['tensionCurve']),
      reveal: _byName(Reveal.values, json['reveal']),
      revealMaxPerTurn: _asInt(json['revealMaxPerTurn']),
      conflictPrimary: _byName(ConflictSource.values, json['conflictPrimary']),
      conflictSecondary:
          _byName(ConflictSource.values, json['conflictSecondary']),
      endingStyle: _byName(EndingStyle.values, json['endingStyle']),
      closureHook: _asBool(json['closureHook']),
      ambientEnabled: _asBool(json['ambientEnabled']),
      ambientTime: _asString(json['ambientTime']),
      ambientWeather: _asString(json['ambientWeather']),
      npcMax: _asInt(json['npcMax']),
      aiPlaysNpc: _asBool(json['aiPlaysNpc']),
      emotionTone: _byName(EmotionTone.values, json['emotionTone']),
      emotionIntensity: _asInt(json['emotionIntensity']),
      addressMode: _byName(AddressMode.values, json['addressMode']),
      addressValue: _asString(json['addressValue']),
      catchphrases: _asStringList(json['catchphrases']),
      anchorTraits: _asStringList(json['anchorTraits']),
      anchorVoiceSample: _asString(json['anchorVoiceSample']),
      sentenceLength: _asInt(json['sentenceLength']),
      metaphorPerParagraph: _asInt(json['metaphorPerParagraph']),
      humorLevel: _asInt(json['humorLevel']),
      dialogueRatio: _asInt(json['dialogueRatio']),
      motifName: _asString(json['motifName']),
      motifEveryN: _asInt(json['motifEveryN']),
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) {
      return null;
    }
    for (final T v in values) {
      if (v.name == raw) {
        return v;
      }
    }
    return null;
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static bool? _asBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is String) {
      final String v = raw.trim().toLowerCase();
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }

  static String? _asString(Object? raw) {
    if (raw is String) {
      final String t = raw.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  static List<String>? _asStringList(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final List<String> out = raw
        .whereType<String>()
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    return out.isEmpty ? null : out;
  }
}

// ---------------------------------------------------------------------------
// 预设方案
//
// 预设**只改细节项**，不动「推进方式 / 沉浸程度 / 字数」这三个基础项 ——
// 那三项是用户在主页明确选过的，一个预设不该悄悄改掉它们。
// 想恢复成「什么都没设」，点「清除」。
// ---------------------------------------------------------------------------

enum StrategyPreset {
  balanced('平衡'),
  cinematic('电影感'),
  webnovel('网文爽'),
  otome('乙女向'),
  mystery('悬疑本'),
  daily('日常向');

  const StrategyPreset(this.label);

  final String label;

  /// 该预设对应的细节项。
  StrategyDetails get details {
    switch (this) {
      case StrategyPreset.balanced:
        return const StrategyDetails(
          pov: Pov.third,
          pacing: Pacing.scene,
          tensionCurve: TensionCurve.wave,
          reveal: Reveal.layered,
          conflictPrimary: ConflictSource.interpersonal,
          endingStyle: EndingStyle.open,
          sentenceLength: 3,
          metaphorPerParagraph: 1,
          humorLevel: 2,
          dialogueRatio: 50,
        );
      case StrategyPreset.cinematic:
        return const StrategyDetails(
          pov: Pov.third,
          pacing: Pacing.scene,
          tensionCurve: TensionCurve.rising,
          reveal: Reveal.layered,
          conflictPrimary: ConflictSource.inner,
          endingStyle: EndingStyle.open,
          closureHook: true,
          ambientEnabled: true,
          sentenceLength: 4,
          metaphorPerParagraph: 2,
          humorLevel: 1,
          dialogueRatio: 40,
        );
      case StrategyPreset.webnovel:
        return const StrategyDetails(
          pov: Pov.third,
          pacing: Pacing.chronological,
          tensionCurve: TensionCurve.spike,
          reveal: Reveal.all,
          conflictPrimary: ConflictSource.interpersonal,
          endingStyle: EndingStyle.closed,
          sentenceLength: 2,
          metaphorPerParagraph: 0,
          humorLevel: 3,
          dialogueRatio: 65,
        );
      case StrategyPreset.otome:
        return const StrategyDetails(
          pov: Pov.first,
          pacing: Pacing.scene,
          tensionCurve: TensionCurve.wave,
          reveal: Reveal.limited,
          conflictPrimary: ConflictSource.interpersonal,
          endingStyle: EndingStyle.open,
          emotionTone: EmotionTone.sweet,
          sentenceLength: 3,
          metaphorPerParagraph: 1,
          humorLevel: 2,
          dialogueRatio: 60,
        );
      case StrategyPreset.mystery:
        return const StrategyDetails(
          pov: Pov.third,
          pacing: Pacing.fragmented,
          tensionCurve: TensionCurve.rising,
          reveal: Reveal.layered,
          revealMaxPerTurn: 1,
          conflictPrimary: ConflictSource.institution,
          conflictSecondary: ConflictSource.inner,
          endingStyle: EndingStyle.closed,
          sentenceLength: 3,
          metaphorPerParagraph: 1,
          humorLevel: 0,
          dialogueRatio: 35,
        );
      case StrategyPreset.daily:
        return const StrategyDetails(
          pov: Pov.first,
          narrativeStructure: NarrativeStructure.slice,
          tensionCurve: TensionCurve.flat,
          reveal: Reveal.all,
          conflictPrimary: ConflictSource.interpersonal,
          endingStyle: EndingStyle.open,
          sentenceLength: 2,
          metaphorPerParagraph: 0,
          humorLevel: 4,
          dialogueRatio: 70,
        );
    }
  }
}

/// 套用一个预设：只替换细节项，基础项原样保留。
PromptStrategy applyPreset(PromptStrategy base, StrategyPreset preset) {
  return base.copyWith(details: preset.details);
}
