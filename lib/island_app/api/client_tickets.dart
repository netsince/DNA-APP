part of 'client.dart';

/// TICKETS 工单
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension TicketsApi on ApiClient {
  // ========================================================================
  //  TICKETS 工单
  // ========================================================================

  /// 我的工单列表（GET `/api/v1/tickets`，需登录）。
  ///
  /// [status] 取 all/open/replied/closed。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  getMyTickets({int page = 1, String status = 'all'}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/tickets',
    ).replace(queryParameters: {'page': '$page', 'status': status});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('工单列表响应格式不正确');
    return _pageOf(d);
  }

  /// 可用工单类别（GET `/api/v1/tickets/categories`，需登录）。
  Future<List<Map<String, dynamic>>> getTicketCategories() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/tickets/categories'));
    final d = data['data'];
    final items = d is Map ? d['items'] : null;
    return items is List
        ? items
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
        : <Map<String, dynamic>>[];
  }

  /// 新建工单（POST `/api/v1/tickets`，需登录）。
  ///
  /// [imageData] 为可选 base64 data URL（单图）。返回新工单 id。
  Future<({int id, String status})> createTicket({
    required String title,
    required String content,
    int? categoryId,
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/tickets'), <String, dynamic>{
      'title': title,
      'content': content,
      'category_id': ?categoryId,
      if (imageData != null && imageData.isNotEmpty) 'image_data': imageData,
    });
    final d = data['data'];
    if (d is! Map) throw Exception('新建工单响应格式不正确');
    return (
      id: (d['id'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? 'open').toString(),
    );
  }

  /// 工单详情（GET `/api/v1/tickets/<id>`，需登录）。
  Future<Map<String, dynamic>> getTicketDetail(int ticketId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/tickets/$ticketId'));
    final d = data['data'];
    if (d is! Map) throw Exception('工单详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 回复工单（POST `/api/v1/tickets/<id>/reply`，需登录）。
  Future<void> replyTicket(
    int ticketId, {
    String content = '',
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/tickets/$ticketId/reply'),
      <String, dynamic>{
        'content': content,
        if (imageData != null && imageData.isNotEmpty) 'image_data': imageData,
      },
    );
  }

  /// 关闭工单（POST `/api/v1/tickets/<id>/close`，需登录）。
  Future<void> closeTicket(int ticketId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/tickets/$ticketId/close'),
      <String, dynamic>{},
    );
  }

  /// 重新打开工单（POST `/api/v1/tickets/<id>/reopen`，需登录）。
  Future<void> reopenTicket(int ticketId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/tickets/$ticketId/reopen'),
      <String, dynamic>{},
    );
  }

}
