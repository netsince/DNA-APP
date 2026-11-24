part of 'client.dart';

/// POINTS 积分
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension PointsApi on ApiClient {
  // ========================================================================
  //  POINTS 积分
  // ========================================================================

  /// 拉取积分变化明细分页（GET `/api/v1/points`，需登录）。
  ///
  /// 返回含 items / balance / page / pages / total。
  Future<PointsData> getPoints({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/points',
    ).replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('积分响应格式不正确');
    final p = _pageOf(d);
    return (
      items: p.items,
      balance: parsePoints(d['balance']),
      page: p.page,
      pages: p.pages,
      total: p.total,
    );
  }

}
