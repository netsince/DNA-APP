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
  unlimited,
}

class PromptStrategy {
  const PromptStrategy({
    required this.advance,
    required this.immersion,
    required this.length,
  });

  factory PromptStrategy.defaults() {
    return const PromptStrategy(
      advance: AdvanceStrategy.forced,
      immersion: ImmersionStrategy.restrained,
      length: LengthStrategy.strict,
    );
  }

  final AdvanceStrategy advance;
  final ImmersionStrategy immersion;
  final LengthStrategy length;

  PromptStrategy copyWith({
    AdvanceStrategy? advance,
    ImmersionStrategy? immersion,
    LengthStrategy? length,
  }) {
    return PromptStrategy(
      advance: advance ?? this.advance,
      immersion: immersion ?? this.immersion,
      length: length ?? this.length,
    );
  }

  Map<String, String> toJson() {
    return <String, String>{
      'advance': advance.name,
      'immersion': immersion.name,
      'length': length.name,
    };
  }

  factory PromptStrategy.fromJson(Map<String, dynamic> json) {
    return PromptStrategy(
      advance: AdvanceStrategy.values.byName(json['advance'] as String),
      immersion: ImmersionStrategy.values.byName(json['immersion'] as String),
      length: LengthStrategy.values.byName(json['length'] as String),
    );
  }
}
