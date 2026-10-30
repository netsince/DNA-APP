/// 社区世界卡的列表项 / 详情项。
///
/// **不含正文** —— 正文（World.toJson() 的原文）要靠
/// ApiClient.downloadWorldText 单独取。列表与详情都只给元信息，这是刻意的：
/// 世界书动辄几百 KB，列表接口带上它就没法翻页了。
class WorldCardSummary {
  const WorldCardSummary({
    required this.id,
    required this.name,
    required this.summary,
    required this.entryCount,
    required this.payloadBytes,
    required this.copyCount,
    this.viewCount = 0,
    this.favorited = false,
    this.favoriteCount = 0,
    required this.tags,
    required this.authorName,
    this.authorUsername = '',
    this.authorAvatar = '',
    required this.createdAt,
    this.updatedAt,
    this.status = '',
    this.isHidden = false,
    this.entryNames = const <String>[],
    this.entryIndex = const <WorldEntryPreview>[],
    this.previewNames = const <String>[],
    this.sampleEntry,
  });

  final String id;
  final String name;
  final String summary;
  final int entryCount;
  final int payloadBytes;
  final int copyCount;

  /// 浏览数（后端一直在数，之前客户端没解析、也没展示）。
  final int viewCount;

  /// 我是否已收藏（详情接口才有；列表项恒为 false）。
  final bool favorited;

  /// 总收藏数（详情接口才有）。
  final int favoriteCount;
  final List<String> tags;
  final String authorName;

  /// 作者用户名 / 头像：详情页要能把作者点进主页（以前只存昵称，点不动）。
  final String authorUsername;
  final String authorAvatar;
  final DateTime? createdAt;

  /// 更新时间（列表项也有）。世界书是会改的，只给创建时间看不出「还在不在维护」。
  final DateTime? updatedAt;

  /// 审核状态（pending / approved / rejected / deleted）。
  ///
  /// 只有「我的世界卡」里才有意义 —— 别人的列表项永远是 approved。
  final String status;

  /// 是否已被下架（作者自己的条目要看得到）。
  final bool isHidden;

  /// 详情页才有：词条名预览（列表项为空）。
  final List<String> entryNames;

  /// 列表卡片用的词条名快照（后端发布/编辑时算好的前 8 条）。
  ///
  /// 卡片上要显示几个词条名，但列表接口**不能去解析 payload**（一页 20 个世界、
  /// 每个几百 KB），所以服务端存了一份快照。
  final List<String> previewNames;

  /// 详情页才有：词条索引（名字 + 人物/名词 + 触发词）。
  ///
  /// 比 [entryNames] 多类型与触发词 —— 详情页靠它做「分组 + 搜索」，和网页版
  /// 同一个形态。**不含正文**，取舍不变。
  final List<WorldEntryPreview> entryIndex;

  /// 详情页才有：1 条示例词条。**原样透传**，不做结构假设 —— 词条字段还会
  /// 继续长（正则激活键、递归扫描、冷却/延迟轮数、装饰符……），这里只取
  /// 用得上的两个键展示，其余不碰。
  final Map<String, dynamic>? sampleEntry;

  static WorldCardSummary fromJson(Map<String, dynamic> json) {
    final Object? author = json['author'];
    String authorName = '';
    String authorUsername = '';
    String authorAvatar = '';
    if (author is Map) {
      authorName = (author['nickname'] ?? author['username'] ?? '')
          .toString()
          .trim();
      authorUsername = (author['username'] ?? '').toString().trim();
      authorAvatar = (author['avatar'] ?? '').toString();
    }
    final Object? names = json['entry_names'];
    final Object? index = json['entry_index'];
    final Object? sample = json['sample_entry'];
    return WorldCardSummary(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      entryCount: _asInt(json['entry_count']),
      payloadBytes: _asInt(json['payload_bytes']),
      copyCount: _asInt(json['copy_count']),
      viewCount: _asInt(json['view_count']),
      favorited: json['favorited'] == true,
      favoriteCount: _asInt(json['favorite_count']),
      tags:
          (json['tags'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      authorName: authorName,
      authorUsername: authorUsername,
      authorAvatar: authorAvatar,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
      status: (json['status'] ?? '').toString(),
      isHidden: json['is_hidden'] == true,
      entryNames: names is List
          ? names.whereType<String>().toList()
          : const <String>[],
      previewNames:
          (json['preview_names'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      entryIndex: index is List
          ? index
                .whereType<Map>()
                .map(
                  (Map e) =>
                      WorldEntryPreview.fromJson(e.cast<String, dynamic>()),
                )
                .where((WorldEntryPreview e) => e.name.isNotEmpty)
                .toList()
          : const <WorldEntryPreview>[],
      sampleEntry: sample is Map ? sample.cast<String, dynamic>() : null,
    );
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString()) ?? 0;
  }

  /// 人读的体积，例如 "182 KB"。
  String get sizeLabel {
    if (payloadBytes <= 0) return '';
    if (payloadBytes < 1024) return '$payloadBytes B';
    if (payloadBytes < 1024 * 1024) {
      return '${(payloadBytes / 1024).round()} KB';
    }
    return '${(payloadBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 状态徽章文案（仅「我的世界卡」用）。返回空串表示不需要徽章。
  String get statusLabel {
    if (status == 'pending') return '待审核';
    if (status == 'rejected') return '已拒绝';
    if (status == 'deleted') return '已撤回';
    if (isHidden) return '已下架';
    return '';
  }
}

/// 一条词条预览：只有名字、类型、触发词。
///
/// 正文（description）刻意不进这里 —— 详情页只给一条示例，其余只给名字，
/// 否则没人愿意再发布世界书。
class WorldEntryPreview {
  const WorldEntryPreview({
    required this.name,
    this.type = 'noun',
    this.keys = const <String>[],
  });

  final String name;

  /// 'person' | 'noun'。后端只归一化成这两类。
  final String type;
  final List<String> keys;

  bool get isPerson => type == 'person';

  /// 搜索用的归一化文本（名字 + 触发词），详情页本地过滤用。
  String get searchText => '$name ${keys.join(' ')}'.toLowerCase();

  static WorldEntryPreview fromJson(Map<String, dynamic> json) {
    final Object? keys = json['keys'];
    return WorldEntryPreview(
      name: (json['name'] ?? '').toString().trim(),
      type: (json['type'] ?? 'noun').toString(),
      keys: keys is List ? keys.whereType<String>().toList() : const <String>[],
    );
  }
}
