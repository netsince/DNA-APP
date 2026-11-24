part of 'client.dart';

/// NOTIFICATIONS 通知
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension NotificationsApi on ApiClient {
  // ========================================================================
  //  NOTIFICATIONS 通知
  // ========================================================================

  /// 拉取通知分页（GET `/api/v1/notifications`，需登录）。
  ///
  /// 返回含 items / page / pages / total / has_next / unread_count。
  Future<NotificationsData> getNotifications({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/notifications',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('通知响应格式不正确');
    final p = _pageOf(d);
    return (
      items: p.items,
      page: p.page,
      pages: p.pages,
      total: p.total,
      hasNext: p.hasNext,
      unreadCount: (d['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 全部标记已读（POST `/api/v1/notifications/read-all`，需登录）。
  Future<void> markAllNotificationsRead() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/notifications/read-all'),
      <String, dynamic>{},
    );
  }

  /// 拉取未读通知数（GET `/api/v1/notifications/unread-count`，需登录）。
  Future<int> getUnreadNotificationCount() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/notifications/unread-count'));
    final d = data['data'];
    if (d is! Map) return 0;
    return (d['unread_count'] as num?)?.toInt() ?? 0;
  }

}
