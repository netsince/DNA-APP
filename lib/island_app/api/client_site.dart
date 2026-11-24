part of 'client.dart';

/// SITE 站点 / 公开 ／ SITE 站点 / 公开（表情包）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension SiteApi on ApiClient {
  // ========================================================================
  //  SITE 站点 / 公开
  // ========================================================================

  /// 拉取公开站点配置（GET /api/v1/site-config）。
  ///
  /// 未配置服务器地址时抛出异常；网络/解析异常向上抛出由调用方决定降级。
  Future<Map<String, dynamic>> getSiteConfig() async {
    final base = await ServerConfig.getBaseUrl();
    final uri = Uri.parse(base).replace(path: '/api/v1/site-config');
    if (base.isEmpty) {
      _logError('GET', uri, error: '未配置服务器地址，无法发起请求');
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(uri);
    // 后端统一返回 {"ok": true, "data": {...}}，兼容直接返回配置对象。
    final d = data['data'] as Map<String, dynamic>?;
    return d ?? data;
  }

  /// 拉取赞助页面数据（GET /api/v1/sponsors）。
  ///
  /// 返回 `data`（含 enabled / title / content / url / sponsors 列表）。未配置服务器或异常时抛错。
  Future<Map<String, dynamic>> getSponsors() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/sponsors'));
    final d = data['data'];
    if (d is! Map) throw Exception('赞助信息响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  // ========================================================================
  //  SITE 站点 / 公开（表情包）
  // ========================================================================

  /// 获取表情包系列列表（GET `/stickers/api`，公开接口）。
  ///
  /// 返回 `[{slug, name, stickers: [{code, image_url}]}]`。
  /// 注意：该接口不经 `/api/v1` 统一包装，响应体直接是 `{"series": [...]}`。
  Future<List<Map<String, dynamic>>> getStickers() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/stickers/api'));
    final series = data['series'];
    return series is List
        ? series
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
        : <Map<String, dynamic>>[];
  }

}
