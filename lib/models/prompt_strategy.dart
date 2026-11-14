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
    );
  }
}
