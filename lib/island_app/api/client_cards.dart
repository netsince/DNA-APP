part of 'client.dart';

/// CARDS 角色卡（浏览 / 详情 / 点赞收藏 / 发布编辑 / 导出导入）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension CardsApi on ApiClient {
  // ========================================================================
  //  CARDS 角色卡（浏览 / 详情 / 点赞收藏 / 发布编辑 / 导出导入）
  // ========================================================================

  /// 拉取首页随机推荐角色卡（GET /api/v1/cards/featured）。
  ///
  /// 返回卡片摘要列表（含 id/name/intro/covers 等）；未配置服务器或异常时抛错，
  /// 由调用方降级处理。可选 [excludeIds]（逗号分隔 id）用于「换一换」去重。
  /// 注意：卡片的 id 是字符串（UUID）。
  Future<List<Map<String, dynamic>>> getFeaturedCards({
    List<String> excludeIds = const [],
  }) async {
    final base = await ServerConfig.getBaseUrl();
    final uri = Uri.parse(base).replace(
      path: '/api/v1/cards/featured',
      queryParameters: excludeIds.isEmpty
          ? null
          : {'exclude': excludeIds.join(',')},
    );
    if (base.isEmpty) {
      _logError('GET', uri, error: '未配置服务器地址，无法发起请求');
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(uri);
    final list = data['data'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
  }

  /// 拉取「刷一刷」角色卡（GET `/api/v1/cards/swipe`）。
  ///
  /// 专用接口：后端**只返回有封面**的卡（热度加权随机 + exclude 去重），
  /// 客户端无需二次过滤。默认每批 12 张。
  Future<List<Map<String, dynamic>>> getSwipeCards({
    List<String> excludeIds = const [],
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/cards/swipe').replace(
      queryParameters: excludeIds.isEmpty
          ? null
          : {'exclude': excludeIds.join(',')},
    );
    final data = await _getJson(uri);
    final list = data['data'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
  }

}
