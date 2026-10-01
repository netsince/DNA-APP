// 角色卡评论相关数据模型（与 `/api/v1/cards/<id>/comments` 接口对齐）。

/// 评论作者（来自 `_user_public`）。
class CommentAuthor {
  const CommentAuthor({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatar,
    this.isSponsor = false,
  });

  final int id;
  final String username;
  final String nickname;
  final String? avatar;

  /// 赞助者：昵称旁红星（与网页版同一字段；旧服务端缺失时为 false）。
  final bool isSponsor;

  factory CommentAuthor.fromJson(Map<String, dynamic> m) {
    final mm = m.map((k, v) => MapEntry(k.toString(), v));
    final rawId = mm['id'];
    return CommentAuthor(
      id: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      username: (mm['username'] ?? '').toString(),
      nickname: (mm['nickname'] ?? mm['display_name'] ?? '').toString(),
      avatar: mm['avatar'] == '' ? null : (mm['avatar']?.toString()),
      isSponsor: mm['is_sponsor'] == true,
    );
  }
}

/// 被回复评论的简短信息。
class CommentReplyTo {
  const CommentReplyTo({required this.id, required this.authorName});

  final int id;
  final String authorName;

  factory CommentReplyTo.fromJson(Map<String, dynamic> m) {
    final mm = m.map((k, v) => MapEntry(k.toString(), v));
    final rawId = mm['id'];
    return CommentReplyTo(
      id: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      authorName: (mm['author_name'] ?? '').toString(),
    );
  }
}

/// 单条评论（含楼中楼子回复）。
class Comment {
  const Comment({
    required this.id,
    required this.content,
    required this.hasImage,
    required this.imageData,
    required this.createdAt,
    required this.author,
    required this.replyTo,
    required this.likeCount,
    required this.liked,
    required this.isPinned,
    required this.moderated,
    required this.isMine,
    required this.isAuthor,
    required this.floor,
    required this.replies,
  });

  final int id;
  final String content;
  final bool hasImage;

  /// 评论图片（WebP base64 data URL），无则为 null。
  final String? imageData;
  final String createdAt;
  final CommentAuthor? author;
  final CommentReplyTo? replyTo;
  final int likeCount;
  final bool liked;
  final bool isPinned;
  final bool moderated;
  final bool isMine;
  final bool isAuthor;
  final int? floor;
  final List<Comment> replies;

  factory Comment.fromJson(Map<String, dynamic> m) {
    final mm = m.map((k, v) => MapEntry(k.toString(), v));
    final rawReplies = mm['replies'];
    final replies = rawReplies is List
        ? rawReplies
            .whereType<Map>()
            .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Comment>[];
    final rawId = mm['id'];
    final rawFloor = mm['floor'];
    final rawLike = mm['like_count'];
    return Comment(
      id: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      content: (mm['content'] ?? '').toString(),
      hasImage: mm['has_image'] == true,
      imageData: (mm['image_data']?.toString().isNotEmpty ?? false)
          ? mm['image_data'].toString()
          : null,
      createdAt: (mm['created_at'] ?? '').toString(),
      author: mm['author'] is Map
          ? CommentAuthor.fromJson(Map<String, dynamic>.from(mm['author'] as Map))
          : null,
      replyTo: mm['reply_to'] is Map
          ? CommentReplyTo.fromJson(
              Map<String, dynamic>.from(mm['reply_to'] as Map))
          : null,
      likeCount:
          rawLike is int ? rawLike : int.tryParse('$rawLike') ?? 0,
      liked: mm['liked'] == true,
      isPinned: mm['is_pinned'] == true,
      moderated: mm['moderated'] == true,
      isMine: mm['is_mine'] == true,
      isAuthor: mm['is_author'] == true,
      floor: rawFloor is int
          ? rawFloor
          : (rawFloor == null ? null : int.tryParse('$rawFloor')),
      replies: replies,
    );
  }

  Comment copyWith({
    bool? liked,
    int? likeCount,
    bool? isPinned,
    List<Comment>? replies,
  }) {
    return Comment(
      id: id,
      content: content,
      hasImage: hasImage,
      imageData: imageData,
      createdAt: createdAt,
      author: author,
      replyTo: replyTo,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
      isPinned: isPinned ?? this.isPinned,
      moderated: moderated,
      isMine: isMine,
      isAuthor: isAuthor,
      floor: floor,
      replies: replies ?? this.replies,
    );
  }
}

/// 评论分页结果。
class CommentPage {
  const CommentPage({
    required this.items,
    required this.page,
    required this.pages,
    required this.total,
    required this.hasNext,
  });

  final List<Comment> items;
  final int page;
  final int pages;
  final int total;
  final bool hasNext;

  factory CommentPage.fromJson(Map<String, dynamic> m) {
    final mm = m.map((k, v) => MapEntry(k.toString(), v));
    final raw = mm['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Comment>[];
    int numOrZero(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return CommentPage(
      items: items,
      page: numOrZero(mm['page']) == 0 ? 1 : numOrZero(mm['page']),
      pages: numOrZero(mm['pages']),
      total: numOrZero(mm['total']),
      hasNext: mm['has_next'] == true,
    );
  }
}
