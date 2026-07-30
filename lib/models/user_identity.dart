class UserIdentity {
  const UserIdentity({
    required this.id,
    required this.name,
    required this.persona,
    this.intro = '',
  });

  final String id;
  final String name;
  final String persona;
  final String intro;

  UserIdentity copyWith({
    String? id,
    String? name,
    String? persona,
    String? intro,
  }) {
    return UserIdentity(
      id: id ?? this.id,
      name: name ?? this.name,
      persona: persona ?? this.persona,
      intro: intro ?? this.intro,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'persona': persona,
      'intro': intro,
    };
  }

  static UserIdentity fromJson(Map<String, dynamic> json) {
    return UserIdentity(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      persona: (json['persona'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
    );
  }
}
