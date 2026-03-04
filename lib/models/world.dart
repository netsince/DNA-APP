class World {
  const World({
    required this.id,
    required this.name,
    required this.summary,
    required this.description,
    required this.tags,
    required this.forbiddenWords,
  });

  final String id;
  final String name;
  final String summary;
  final String description;
  final List<String> tags;
  final List<String> forbiddenWords;

  World copyWith({
    String? name,
    String? summary,
    String? description,
    List<String>? tags,
    List<String>? forbiddenWords,
  }) {
    return World(
      id: id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      forbiddenWords: forbiddenWords ?? this.forbiddenWords,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'summary': summary,
      'description': description,
      'tags': tags,
      'forbiddenWords': forbiddenWords,
    };
  }

  static World fromJson(Map<String, dynamic> json) {
    return World(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? <String>[],
      forbiddenWords:
          (json['forbiddenWords'] as List?)?.whereType<String>().toList() ?? <String>[],
    );
  }
}
