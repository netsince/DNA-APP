class Role {
  const Role({
    required this.id,
    required this.name,
    required this.gender,
    required this.persona,
    required this.intro,
    required this.opening,
    required this.tags,
    required this.images,
  });

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;
  final List<String> tags;
  final Map<String, String> images;

  Role copyWith({
    String? name,
    String? gender,
    String? persona,
    String? intro,
    String? opening,
    List<String>? tags,
    Map<String, String>? images,
  }) {
    return Role(
      id: id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      persona: persona ?? this.persona,
      intro: intro ?? this.intro,
      opening: opening ?? this.opening,
      tags: tags ?? this.tags,
      images: images ?? this.images,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'gender': gender,
      'persona': persona,
      'intro': intro,
      'opening': opening,
      'tags': tags,
      'images': images,
    };
  }

  static Role fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      gender: (json['gender'] as String?) ?? '无性',
      persona: (json['persona'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
      opening: (json['opening'] as String?) ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? <String>[],
      images: (json['images'] as Map?)
              ?.map((Object? key, Object? value) => MapEntry('$key', '$value')) ??
          <String, String>{},
    );
  }
}
