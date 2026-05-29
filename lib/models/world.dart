class World {
  const World({
    required this.id,
    required this.name,
    required this.summary,
    required this.description,
    required this.tags,
    required this.forbiddenWords,
    required this.entries,
    this.archived = false,
  });

  final String id;
  final String name;
  final String summary;
  final String description;
  final List<String> tags;
  final List<String> forbiddenWords;
  final List<WorldEntry> entries;
  final bool archived;

  World copyWith({
    String? name,
    String? summary,
    String? description,
    List<String>? tags,
    List<String>? forbiddenWords,
    List<WorldEntry>? entries,
    bool? archived,
  }) {
    return World(
      id: id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      forbiddenWords: forbiddenWords ?? this.forbiddenWords,
      entries: entries ?? this.entries,
      archived: archived ?? this.archived,
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
      'entries': entries.map((WorldEntry entry) => entry.toJson()).toList(),
      'archived': archived,
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
      entries: (json['entries'] as List?)
              ?.whereType<Map>()
              .map((Map entry) => WorldEntry.fromJson(entry.cast<String, dynamic>()))
              .toList() ??
          <WorldEntry>[],
      archived: (json['archived'] as bool?) ?? false,
    );
  }
}

enum WorldEntryType {
  noun,
  person,
}

enum WorldPersonGender {
  male,
  female,
  other,
}

enum WorldPersonStatus {
  normal,
  dead,
}

WorldEntryType _entryTypeFromJson(String? raw) {
  switch (raw) {
    case 'person':
      return WorldEntryType.person;
    case 'noun':
    default:
      return WorldEntryType.noun;
  }
}

String _entryTypeToJson(WorldEntryType type) {
  switch (type) {
    case WorldEntryType.person:
      return 'person';
    case WorldEntryType.noun:
      return 'noun';
  }
}

WorldPersonGender? _genderFromJson(String? raw) {
  switch (raw) {
    case 'male':
      return WorldPersonGender.male;
    case 'female':
      return WorldPersonGender.female;
    case 'other':
      return WorldPersonGender.other;
  }
  return null;
}

String? _genderToJson(WorldPersonGender? gender) {
  switch (gender) {
    case WorldPersonGender.male:
      return 'male';
    case WorldPersonGender.female:
      return 'female';
    case WorldPersonGender.other:
      return 'other';
    case null:
      return null;
  }
}

WorldPersonStatus? _statusFromJson(String? raw) {
  switch (raw) {
    case 'normal':
      return WorldPersonStatus.normal;
    case 'dead':
      return WorldPersonStatus.dead;
  }
  return null;
}

String? _statusToJson(WorldPersonStatus? status) {
  switch (status) {
    case WorldPersonStatus.normal:
      return 'normal';
    case WorldPersonStatus.dead:
      return 'dead';
    case null:
      return null;
  }
}

class WorldEntryRelation {
  const WorldEntryRelation({
    required this.targetId,
    required this.content,
  });

  final String targetId;
  final String content;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'targetId': targetId,
      'content': content,
    };
  }

  static WorldEntryRelation fromJson(Map<String, dynamic> json) {
    return WorldEntryRelation(
      targetId: (json['targetId'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
    );
  }
}

class WorldEntry {
  const WorldEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.gender,
    this.age,
    this.status,
    this.relation,
  });

  final String id;
  final String name;
  final String description;
  final WorldEntryType type;
  final WorldPersonGender? gender;
  final String? age;
  final WorldPersonStatus? status;
  final WorldEntryRelation? relation;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'type': _entryTypeToJson(type),
      'gender': _genderToJson(gender),
      'age': age,
      'status': _statusToJson(status),
      'relation': relation?.toJson(),
    };
  }

  static WorldEntry fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? relationJson =
        json['relation'] is Map ? (json['relation'] as Map).cast<String, dynamic>() : null;
    return WorldEntry(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      type: _entryTypeFromJson(json['type'] as String?),
      gender: _genderFromJson(json['gender'] as String?),
      age: json['age'] as String?,
      status: _statusFromJson(json['status'] as String?),
      relation:
          relationJson == null ? null : WorldEntryRelation.fromJson(relationJson),
    );
  }
}
