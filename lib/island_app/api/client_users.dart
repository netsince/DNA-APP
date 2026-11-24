part of 'client.dart';

/// USERS 用户（主页 / 关注 / 粉丝 / 搜索） ／ USERS 用户（主页 / 评论 / 关注 / 粉丝）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension UsersApi on ApiClient {
  // ========================================================================
  //  USERS 用户（主页 / 关注 / 粉丝 / 搜索）
  // ========================================================================

  /// 关注/取消关注某作者（POST `/api/v1/users/<username>/follow`，需登录）。
  ///
  /// 返回是否「已关注」。未登录（401）或关注自己时抛异常。
  Future<bool> toggleFollow(String username) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/users/$username/follow'),
      <String, dynamic>{},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('关注响应格式不正确');
    final m = d.map((k, v) => MapEntry(k.toString(), v));
    return m['following'] == true;
  }

  // ========================================================================
  //  USERS 用户（主页 / 评论 / 关注 / 粉丝）
  // ========================================================================

  /// 拉取指定用户主页（GET `/api/v1/users/<username>`，可带 page 分页卡片）。
  ///
  /// 返回含 user / follower_count / following_count / cards 等（公开接口）。
  Future<Map<String, dynamic>> getUserProfile(
    String username, {
    int page = 1,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/users/$username',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('用户主页响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取用户的角色卡评论（GET `/api/v1/users/<username>/comments`）。
  Future<Map<String, dynamic>> getUserComments(
    String username, {
    int page = 1,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/users/$username/comments',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('用户评论响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取用户的茶馆帖子（GET `/api/v1/users/<username>/teahouse`）。
  /// 返回 `{items, page, pages, total, has_next}`，item 结构与茶馆 feed 一致。
  Future<Map<String, dynamic>> getUserTeahousePosts(
    String username, {
    int page = 1,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/users/$username/teahouse',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('用户茶馆帖子响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取粉丝列表（GET `/api/v1/users/<username>/followers`）。
  Future<Map<String, dynamic>> getFollowers(String username, {int page = 1}) =>
      _getFollowList(username, 'followers', page);

  /// 拉取关注列表（GET `/api/v1/users/<username>/following`）。
  Future<Map<String, dynamic>> getFollowing(String username, {int page = 1}) =>
      _getFollowList(username, 'following', page);

  Future<Map<String, dynamic>> _getFollowList(
    String username,
    String kind,
    int page,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/users/$username/$kind',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('关注列表响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

}
