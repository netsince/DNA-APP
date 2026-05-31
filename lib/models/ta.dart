import 'dialogue_style.dart';

class TA {
  const TA({
    required this.id,
    required this.name,
    required this.gender,
    required this.persona,
    required this.intro,
    required this.opening,
    required this.tags,
    required this.images,
    required this.dialogueStyle,
    this.archived = false,
    this.originalLink,
  });

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;
  final List<String> tags;
  final Map<String, String> images;
  final List<DialogueTurn> dialogueStyle;
  final bool archived;
  final String? originalLink;

  TA copyWith({
    String? name,
    String? gender,
    String? persona,
    String? intro,
    String? opening,
    List<String>? tags,
    Map<String, String>? images,
    List<DialogueTurn>? dialogueStyle,
    bool? archived,
    String? originalLink,
  }) {
    return TA(
      id: id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      persona: persona ?? this.persona,
      intro: intro ?? this.intro,
      opening: opening ?? this.opening,
      tags: tags ?? this.tags,
      images: images ?? this.images,
      dialogueStyle: dialogueStyle ?? this.dialogueStyle,
      archived: archived ?? this.archived,
      originalLink: originalLink ?? this.originalLink,
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
      'dialogueStyle': dialogueStyle.map((DialogueTurn t) => t.toJson()).toList(),
      'archived': archived,
      'originalLink': originalLink,
    };
  }

  static TA fromJson(Map<String, dynamic> json) {
    final List<dynamic>? raw = json['dialogueStyle'] as List<dynamic>?;
    return TA(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      gender: (json['gender'] as String?) ?? '无性',
      persona: (json['persona'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
      opening: (json['opening'] as String?) ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? <String>[],
      images: switch (json['images']) {
        Map m => m.map((key, value) => MapEntry('$key', '$value')),
        _ => <String, String>{},
      },
      dialogueStyle: raw == null
          ? <DialogueTurn>[]
          : raw.whereType<Map<String, dynamic>>().map(DialogueTurn.fromJson).toList(),
      archived: (json['archived'] as bool?) ?? false,
      originalLink: json['originalLink'] as String?,
    );
  }
}
