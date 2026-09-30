/// 茶馆帖子作者（对应后端 `_user_public` 的轻量字段）。
class TeaPostAuthor {
  const TeaPostAuthor({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.verified,
  });

  factory TeaPostAuthor.fromJson(Map<String, dynamic> m) => TeaPostAuthor(
        id: (m['id'] ?? 0).toString(),
        username: (m['username'] ?? '').toString(),
        nickname: (m['nickname'] ?? '').toString(),
        avatar: (m['avatar'] ?? '').toString(),
        verified: m['verified'] == true,
      );

  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final bool verified;

  String get displayName => nickname.isNotEmpty ? nickname : username;
}

/// 茶馆帖子配图（单图）。
class TeaPostImage {
  const TeaPostImage({required this.id, required this.url});

  factory TeaPostImage.fromJson(Map<String, dynamic> m) => TeaPostImage(
        id: (m['id'] ?? 0).toString(),
        url: (m['url'] ?? '').toString(),
      );

  final String id;
  final String url;
}

/// 帖子关联的角色卡摘要（id + name + covers 封面路径）。
class TeaPostCard {
  const TeaPostCard({
    required this.id,
    required this.name,
    this.covers = const <String, String>{},
  });

  factory TeaPostCard.fromJson(Map<String, dynamic> m) {
    final coversRaw = m['covers'];
    final covers = <String, String>{};
    if (coversRaw is Map) {
      coversRaw.forEach((k, v) {
        covers[k.toString()] = (v ?? '').toString();
      });
    }
    return TeaPostCard(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      covers: covers,
    );
  }

  final String id;
  final String name;

  /// 槽位 -> 相对图片路径（如 {"square": "/card-image/123/square"}），空表无封面。
  final Map<String, String> covers;

  /// 第一张封面路径（空串表示无封面）。
  String get cover {
    for (final v in covers.values) {
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}

/// 帖子话题（id + name）。
class TeaPostTopic {
  const TeaPostTopic({required this.id, required this.name});

  factory TeaPostTopic.fromJson(Map<String, dynamic> m) => TeaPostTopic(
        id: (m['id'] ?? 0).toString(),
        name: (m['name'] ?? '').toString(),
      );

  final String id;
  final String name;
}

/// 帖子统计（对应后端 `_build_stats` 返回的 stats）。
class TeaPostStats {
  const TeaPostStats({
    required this.likeCount,
    required this.liked,
    required this.replyCount,
    required this.favorited,
    required this.topics,
  });

  factory TeaPostStats.fromJson(Map<String, dynamic>? m) => TeaPostStats(
        likeCount: m == null ? 0 : (m['like_count'] as num?)?.toInt() ?? 0,
        liked: m != null && m['liked'] == true,
        replyCount: m == null ? 0 : (m['reply_count'] as num?)?.toInt() ?? 0,
        favorited: m != null && m['favorited'] == true,
        topics: m == null
            ? const <TeaPostTopic>[]
            : (m['topics'] is List
                ? (m['topics'] as List)
                    .whereType<Map>()
                    .map((e) => TeaPostTopic.fromJson(
                        e.map((k, v) => MapEntry(k.toString(), v))))
                    .toList()
                : const <TeaPostTopic>[]),
      );

  final int likeCount;
  final bool liked;
  final int replyCount;
  final bool favorited;
  final List<TeaPostTopic> topics;

  TeaPostStats copyWith({int? likeCount, bool? liked, int? replyCount, bool? favorited}) =>
      TeaPostStats(
        likeCount: likeCount ?? this.likeCount,
        liked: liked ?? this.liked,
        replyCount: replyCount ?? this.replyCount,
        favorited: favorited ?? this.favorited,
        topics: topics,
      );
}

/// 茶馆帖子（对应后端 `_teapost_item`）。
class TeaPost {
  const TeaPost({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.author,
    required this.stats,
    this.image,
    this.card,
    this.parentId,
    this.isDeleted = false,
    this.isHidden = false,
  });

  factory TeaPost.fromJson(Map<String, dynamic> m) {
    final authorRaw = m['author'];
    final imageRaw = m['image'];
    final cardRaw = m['card'];
    final statsRaw = m['stats'];
    return TeaPost(
      id: (m['id'] ?? 0).toString(),
      content: (m['content'] ?? '').toString(),
      createdAt: (m['created_at'] ?? '').toString(),
      author: authorRaw is Map
          ? TeaPostAuthor.fromJson(
              authorRaw.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      image: imageRaw is Map
          ? TeaPostImage.fromJson(
              imageRaw.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      card: cardRaw is Map
          ? TeaPostCard.fromJson(
              cardRaw.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      parentId: m['parent_id'] == null
          ? null
          : (m['parent_id'] is num
              ? (m['parent_id'] as num).toInt()
              : int.tryParse('${m['parent_id']}')),
      isDeleted: m['is_deleted'] == true,
      isHidden: m['is_hidden'] == true,
      stats: TeaPostStats.fromJson(
          statsRaw is Map ? Map<String, dynamic>.from(statsRaw) : null),
    );
  }

  final String id;
  final String content;
  final String createdAt;
  final TeaPostAuthor? author;
  final TeaPostImage? image;
  final TeaPostCard? card;
  final int? parentId;
  final bool isDeleted;
  final bool isHidden;
  final TeaPostStats stats;

  int get idInt => int.tryParse(id) ?? 0;

  TeaPost copyWith({TeaPostStats? stats}) => TeaPost(
        id: id,
        content: content,
        createdAt: createdAt,
        author: author,
        image: image,
        card: card,
        parentId: parentId,
        isDeleted: isDeleted,
        isHidden: isHidden,
        stats: stats ?? this.stats,
      );
}
