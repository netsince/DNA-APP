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

class PromptStrategy {
  const PromptStrategy({
    required this.advance,
    required this.immersion,
    required this.length,
    this.customMinChars,
    this.customMaxChars,
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

  PromptStrategy copyWith({
    AdvanceStrategy? advance,
    ImmersionStrategy? immersion,
    LengthStrategy? length,
    int? customMinChars,
    int? customMaxChars,
  }) {
    return PromptStrategy(
      advance: advance ?? this.advance,
      immersion: immersion ?? this.immersion,
      length: length ?? this.length,
      customMinChars: customMinChars ?? this.customMinChars,
      customMaxChars: customMaxChars ?? this.customMaxChars,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'advance': advance.name,
      'immersion': immersion.name,
      'length': length.name,
      if (customMinChars != null) 'customMinChars': customMinChars,
      if (customMaxChars != null) 'customMaxChars': customMaxChars,
    };
  }

  factory PromptStrategy.fromJson(Map<String, dynamic> json) {
    return PromptStrategy(
      advance: AdvanceStrategy.values.byName(json['advance'] as String),
      immersion: ImmersionStrategy.values.byName(json['immersion'] as String),
      length: LengthStrategy.values.byName(json['length'] as String),
      customMinChars: json['customMinChars'] as int?,
      customMaxChars: json['customMaxChars'] as int?,
    );
  }
}
