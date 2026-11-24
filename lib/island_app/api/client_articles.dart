part of 'client.dart';

/// ARTICLES 文章
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension ArticlesApi on ApiClient {
  // ========================================================================
  //  ARTICLES 文章
  // ========================================================================

  /// 拉取官方文章分页（GET `/api/v1/articles`）。
  ///
  /// 支持 [sort]（new/old/updated）与 [query] 搜索，与网页版同一口径。
  Future<ArticlesData> getArticles({
    int page = 1,
    String sort = 'new',
    String query = '',
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/articles').replace(
      queryParameters: <String, String>{
        'page': '$page',
        'sort': sort,
        if (query.isNotEmpty) 'q': query,
      },
    );
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('文章响应格式不正确');
    return _pageOf(d);
  }

  /// 拉取文章详情（GET `/api/v1/articles/<id>`），返回含正文 HTML 的 Map。
  Future<Map<String, dynamic>> getArticleDetail(int id) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/articles/$id'));
    final d = data['data'];
    if (d is! Map) throw Exception('文章详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

}
