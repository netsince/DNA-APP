part of 'client.dart';

/// COMMENTS 角色卡评论
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension CommentsApi on ApiClient {
  // ========================================================================
  //  COMMENTS 角色卡评论
  // ========================================================================

  /// 拉取角色卡评论列表（GET `/api/v1/cards/<card_id>/comments`）。
  ///
  /// 支持 `sort`（latest/hottest）与 `onlyAuthor`（只看作者）。未配置服务器或异常时抛错。
  Future<CommentPage> getCardComments(
    String cardId, {
    int page = 1,
    String sort = 'latest',
    bool onlyAuthor = false,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final query = <String, String>{
      'page': '$page',
      'sort': sort,
      if (onlyAuthor) 'only_author': '1',
    };
    final uri = _apiUri(
      '/api/v1/cards/$cardId/comments',
    ).replace(queryParameters: query);
    final data = await _getJson(uri);
    final d = data['data'] is Map ? data['data'] as Map : data;
    return CommentPage.fromJson(Map<String, dynamic>.from(d));
  }

  /// 发表评论（POST `/api/v1/cards/<card_id>/comments`，需登录）。
  ///
  /// `replyToId` 指定楼中楼回复目标。返回新建评论 id。内容为空/超长由后端校验。
  Future<int> postCardComment(
    String cardId,
    String content, {
    int? replyToId,
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{'content': content};
    if (replyToId != null) body['reply_to_id'] = replyToId;
    if (imageData != null && imageData.isNotEmpty) {
      body['image_data'] = imageData;
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments'),
      body,
    );
    final d = data['data'];
    final rawId = d is Map ? d['id'] : null;
    return rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
  }

  /// 评论点赞/取消（POST `/api/v1/cards/<card_id>/comments/<id>/like`，需登录）。
  ///
  /// 返回切换后的 `(liked, count)`。
  Future<({bool liked, int count})> toggleCommentLike(
    String cardId,
    int commentId,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/like'),
      <String, dynamic>{},
    );
    final d = data['data'];
    final liked = d is Map ? d['liked'] == true : false;
    final count = d is Map
        ? (d['count'] is int
              ? d['count'] as int
              : int.tryParse('${d['count']}') ?? 0)
        : 0;
    return (liked: liked, count: count);
  }

  /// 评论置顶/取消置顶（POST `/api/v1/cards/<card_id>/comments/<id>/pin`，仅卡作者）。
  ///
  /// 返回切换后的 `is_pinned`。
  Future<bool> toggleCommentPin(String cardId, int commentId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/pin'),
      <String, dynamic>{},
    );
    final d = data['data'];
    return d is Map ? d['is_pinned'] == true : false;
  }

  /// 删除评论（POST `/api/v1/cards/<card_id>/comments/<id>/delete`，仅评论作者）。
  Future<void> deleteComment(String cardId, int commentId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/delete'),
      <String, dynamic>{},
    );
  }

  /// 从后端 `data` 解析标准分页结果，返回统一的
  /// `(items, page, pages, total, hasNext)`；字段缺失时给出安全默认值。
  ///
  /// 供各分页方法复用，避免重复写 `items is List ? ... : []` 的解析样板。
  ({
    List<Map<String, dynamic>> items,
    int page,
    int pages,
    int total,
    bool hasNext,
  })
  _pageOf(Object? raw) {
    final d = raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final items = d['items'];
    final list = items is List
        ? items
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
        : <Map<String, dynamic>>[];
    return (
      items: list,
      page: (d['page'] as num?)?.toInt() ?? 1,
      pages: (d['pages'] as num?)?.toInt() ?? 1,
      total: (d['total'] as num?)?.toInt() ?? 0,
      hasNext: d['has_next'] == true,
    );
  }

  Uri _apiUri(String path) {
    // ServerConfig.getBaseUrl 是同步缓存读取（main 启动已预热）。
    final base = ServerConfig.cachedBaseUrl;
    return Uri.parse(base).replace(path: path);
  }

}
