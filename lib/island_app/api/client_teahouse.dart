part of 'client.dart';

/// TEAHOUSE 茶馆（Feed / 详情 / 话题 / 收藏 / 发帖 / 回复 / 点赞收藏 / 编辑删除 / 搜索） ／ TEAHOUSE 茶馆（发帖/回复时关联卡片搜索）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension TeahouseApi on ApiClient {
  // ========================================================================
  //  TEAHOUSE 茶馆（Feed / 详情 / 话题 / 收藏 / 发帖 / 回复 / 点赞收藏 / 编辑删除 / 搜索）
  // ========================================================================

  /// 拉取茶馆 Feed（GET `/api/v1/teahouse/posts`）。
  ///
  /// 支持 `sort`（hot/new）与可选 `topicId` 过滤。返回含 items（_teapost_item Map）。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  getTeahousePosts({int page = 1, String sort = 'hot', int? topicId}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final query = <String, String>{
      'page': '$page',
      'sort': sort,
      if (topicId != null) 'topic_id': '$topicId',
    };
    final uri = _apiUri(
      '/api/v1/teahouse/posts',
    ).replace(queryParameters: query);
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆 Feed 响应格式不正确');
    return _pageOf(d);
  }

  /// 拉取茶馆帖子详情（GET `/api/v1/teahouse/posts/<id>`）。
  ///
  /// 返回含 post / chain（原帖链）/ replies（分页）。可传 [page]/[sort] 分页回复。
  Future<Map<String, dynamic>> getTeahousePostDetail(
    int postId, {
    int page = 1,
    String sort = 'hot',
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/teahouse/posts/$postId',
    ).replace(queryParameters: {'page': '$page', 'sort': sort});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆帖子详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取茶馆热门话题（GET `/api/v1/teahouse/topics`）。
  Future<List<Map<String, dynamic>>> getTeahouseTopics() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/teahouse/topics'));
    final d = data['data'];
    final list = d is List
        ? d
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
        : <Map<String, dynamic>>[];
    return list;
  }

  /// 拉取某话题下的帖子（GET `/api/v1/teahouse/topics/<id>`）。
  Future<
    ({
      Map<String, dynamic>? topic,
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  getTeahouseTopicPosts(int topicId, {int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/teahouse/topics/$topicId',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('话题帖子响应格式不正确');
    final topicRaw = d['topic'];
    final topic = topicRaw is Map
        ? topicRaw.map((k, v) => MapEntry(k.toString(), v))
        : null;
    final p = _pageOf(d);
    return (
      topic: topic,
      items: p.items,
      page: p.page,
      pages: p.pages,
      total: p.total,
      hasNext: p.hasNext,
    );
  }

  /// 拉取我收藏的茶馆帖子（GET `/api/v1/teahouse/favorites`，需登录）。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  getTeahouseFavorites({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/teahouse/favorites',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆收藏响应格式不正确');
    return _pageOf(d);
  }

  /// 发布茶馆帖子（POST `/api/v1/teahouse/posts`，需登录）。
  ///
  /// [content] 正文；[cardId] 可选关联角色卡；[imageData] 可选单图 base64 data URL；
  /// [topic] 可选话题名。返回新帖 id。
  Future<int> createTeahousePost({
    required String content,
    String? cardId,
    String? imageData,
    String? topic,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (imageData != null && imageData.isNotEmpty)
        'images': <String>[imageData],
      if (topic != null && topic.isNotEmpty) 'topic': topic,
    };
    final data = await _postJson(_apiUri('/api/v1/teahouse/posts'), body);
    final d = data['data'];
    final id = d is Map ? d['id'] : null;
    return id is int ? id : int.tryParse('$id') ?? 0;
  }

  /// 回复茶馆帖子（POST `/api/v1/teahouse/posts/<id>/reply`，需登录）。
  Future<int> replyTeahousePost(
    int postId,
    String content, {
    String? cardId,
    String? topic,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
    };
    final data = await _postJson(
      _apiUri('/api/v1/teahouse/posts/$postId/reply'),
      body,
    );
    final d = data['data'];
    final id = d is Map ? d['id'] : null;
    return id is int ? id : int.tryParse('$id') ?? 0;
  }

  /// 点赞/取消点赞茶馆帖子（POST `/api/v1/teahouse/posts/<id>/like`，需登录）。
  Future<({bool liked, int count})> toggleTeahouseLike(int postId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/teahouse/posts/$postId/like'),
      <String, dynamic>{},
    );
    final d = data['data'];
    return (
      liked: d is Map && d['liked'] == true,
      count: d is Map
          ? (d['count'] is int
                ? d['count'] as int
                : int.tryParse('${d['count']}') ?? 0)
          : 0,
    );
  }

  /// 收藏/取消收藏茶馆帖子（POST `/api/v1/teahouse/posts/<id>/favorite`，需登录）。
  Future<({bool favorited, int count})> toggleTeahouseFavorite(
    int postId,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/teahouse/posts/$postId/favorite'),
      <String, dynamic>{},
    );
    final d = data['data'];
    return (
      favorited: d is Map && d['favorited'] == true,
      count: d is Map
          ? (d['count'] is int
                ? d['count'] as int
                : int.tryParse('${d['count']}') ?? 0)
          : 0,
    );
  }

  /// 编辑茶馆帖子（POST `/api/v1/teahouse/posts/<id>/edit`，需登录）。
  ///
  /// [content] 新正文；[cardId] 提供则关联；[cardRemoved] true 则解除关联；
  /// [topic] 提供则设置/清除话题；[imageRemoved] true 则移除配图；
  /// [imageData] 提供则用新图整体替换配图（data URL 图片字符串）。
  Future<void> editTeahousePost(
    int postId, {
    required String content,
    String? cardId,
    bool cardRemoved = false,
    String? topic,
    bool imageRemoved = false,
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (cardRemoved) 'card_removed': true,
      'topic': ?topic,
      if (imageRemoved) 'image_removed': true,
      if (imageData != null && imageData.isNotEmpty) 'images': [imageData],
    };
    await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/edit'), body);
  }

  /// 删除茶馆帖子（POST `/api/v1/teahouse/posts/<id>/delete`，需登录，作者或超管）。
  Future<void> deleteTeahousePost(int postId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/teahouse/posts/$postId/delete'),
      <String, dynamic>{},
    );
  }

  // ========================================================================
  //  TEAHOUSE 茶馆（发帖/回复时关联卡片搜索）
  // ========================================================================

  /// 发帖时搜索可关联的角色卡（GET `/api/v1/teahouse/card-search`，需登录）。
  ///
  /// 返回卡片摘要（id/name/intro/cover/author）列表，供发帖/回复时关联。
  Future<List<Map<String, dynamic>>> searchLinkCards(String query) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    if (query.trim().isEmpty) return const <Map<String, dynamic>>[];
    final uri = _apiUri(
      '/api/v1/teahouse/card-search',
    ).replace(queryParameters: {'q': query});
    final data = await _getJson(uri);
    final d = data['data'];
    final items = d is Map ? d['items'] : null;
    return items is List
        ? items
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
        : <Map<String, dynamic>>[];
  }

}
