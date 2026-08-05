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
    String? id,
    String? name,
    String? summary,
    String? description,
    List<String>? tags,
    List<String>? forbiddenWords,
    List<WorldEntry>? entries,
    bool? archived,
  }) {
    return World(
      id: id ?? this.id,
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
    this.keys = const <String>[],
    this.keyRegex,
    this.caseSensitive = false,
    this.matchWholeWords = false,
    this.recursive = false,
    this.order = 0,
    this.cooldownRounds = 0,
    this.delayRounds = 0,
    this.decorator,
  });

  final String id;
  final String name;
  final String description;
  final WorldEntryType type;
  final WorldPersonGender? gender;
  final String? age;
  final WorldPersonStatus? status;
  final WorldEntryRelation? relation;

  /// 附加激活关键词：除 [name] 外，命中任意一个也触发该词条。空表示不附加。
  final List<String> keys;

  /// 正则激活键：非空时按该正则匹配对话文本，命中即触发。可补充/替代 [name] 与 [keys]。
  final String? keyRegex;

  /// 大小写敏感：true 时关键词按大小写精确匹配；false 时忽略大小写（默认）。
  final bool caseSensitive;

  /// 全词匹配：true 时只匹配完整词（避免「宝」命中「宝贝」），默认 false。
  final bool matchWholeWords;

  /// 递归扫描：true 时该词条被激活后，其描述文本也会作为新的扫描文本，
  /// 以命中更多词条（多级联动）。默认 false。
  final bool recursive;

  /// 排序序号：预算裁剪时按 order 从小到大排序，优先级更高的词条先注入。
  final int order;

  /// 冷却轮数：词条激活后进入冷却，在该轮数内同名键不再重复触发。0 表示无冷却。
  final int cooldownRounds;

  /// 延迟轮数：关键词出现后延迟若干轮再激活。0 表示立即激活。
  final int delayRounds;

  /// 装饰符：'activate' 强制激活（跳过冷却）、'dont_activate' 禁止激活、null 正常。
  final String? decorator;

  WorldEntry copyWith({
    String? id,
    String? name,
    String? description,
    WorldEntryType? type,
    WorldPersonGender? gender,
    String? age,
    WorldPersonStatus? status,
    WorldEntryRelation? relation,
    List<String>? keys,
    String? keyRegex,
    bool? caseSensitive,
    bool? matchWholeWords,
    bool? recursive,
    int? order,
    int? cooldownRounds,
    int? delayRounds,
    String? decorator,
  }) {
    return WorldEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      status: status ?? this.status,
      relation: relation ?? this.relation,
      keys: keys ?? this.keys,
      keyRegex: keyRegex ?? this.keyRegex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      matchWholeWords: matchWholeWords ?? this.matchWholeWords,
      recursive: recursive ?? this.recursive,
      order: order ?? this.order,
      cooldownRounds: cooldownRounds ?? this.cooldownRounds,
      delayRounds: delayRounds ?? this.delayRounds,
      decorator: decorator ?? this.decorator,
    );
  }

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
      'keys': keys,
      'keyRegex': keyRegex,
      'caseSensitive': caseSensitive,
      'matchWholeWords': matchWholeWords,
      'recursive': recursive,
      'order': order,
      'cooldownRounds': cooldownRounds,
      'delayRounds': delayRounds,
      'decorator': decorator,
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
      keys: (json['keys'] as List?)?.whereType<String>().toList() ?? <String>[],
      keyRegex: json['keyRegex'] as String?,
      caseSensitive: (json['caseSensitive'] as bool?) ?? false,
      matchWholeWords: (json['matchWholeWords'] as bool?) ?? false,
      recursive: (json['recursive'] as bool?) ?? false,
      order: (json['order'] as int?) ?? 0,
      cooldownRounds: (json['cooldownRounds'] as int?) ?? 0,
      delayRounds: (json['delayRounds'] as int?) ?? 0,
      decorator: json['decorator'] as String?,
    );
  }
}
