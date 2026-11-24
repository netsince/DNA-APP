part of 'client.dart';

/// MY 我的（角色卡 / 收藏 / 点赞 / 资料）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension MyApi on ApiClient {
  // ========================================================================
  //  MY 我的（角色卡 / 收藏 / 点赞 / 资料）
  // ========================================================================

  /// 拉取"我的角色卡"分页列表（GET /api/v1/my/cards，需登录）。
  Future<Map<String, dynamic>> getMyCards({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/my/cards',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('我的角色卡响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取"我收藏的"角色卡分页列表（GET /api/v1/my/favorites，需登录）。
  Future<Map<String, dynamic>> getMyFavorites({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/my/favorites',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('我的收藏响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取"我点赞的"角色卡分页列表（GET /api/v1/my/likes，需登录）。
  Future<Map<String, dynamic>> getMyLikes({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/my/likes',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('我的点赞响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 获取自己的完整资料（GET `/api/v1/me/profile`，需登录）。
  ///
  /// 返回 nickname/avatar/bio/location/website/birthday/notify_like 等，供编辑页预填。
  Future<Map<String, dynamic>> getMyProfile() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/me/profile'));
    final d = data['data'];
    if (d is! Map) throw Exception('个人资料响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 更新个人资料（POST `/api/v1/me/profile`，需登录）。
  ///
  /// [payload]：nickname/bio/location/website/birthday/notify_like/avatar_data_url/remove_avatar。
  /// 返回更新后的资料。
  Future<Map<String, dynamic>> updateMyProfile(
    Map<String, dynamic> payload,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/me/profile'), payload);
    final d = data['data'];
    if (d is! Map) throw Exception('更新资料响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

}
