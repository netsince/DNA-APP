part of 'client.dart';

/// SEARCH 搜索（卡片 / 用户 / 茶馆帖子 / 联想）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension SearchApi on ApiClient {
  // ========================================================================
  //  SEARCH 搜索（卡片 / 用户 / 茶馆帖子 / 联想）
  // ========================================================================

  /// 搜索茶馆帖子（GET `/api/v1/teahouse/search`）。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  searchTeahousePosts(String query, {int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/teahouse/search',
    ).replace(queryParameters: {'q': query, 'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆搜索响应格式不正确');
    return _pageOf(d);
  }

  /// 搜索角色卡（GET `/api/v1/cards/search`）。
  ///
  /// `sort` 取 relevance/hot/new；`tag` 可选标签过滤。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  searchCards(
    String query, {
    int page = 1,
    String sort = 'relevance',
    String? tag,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/cards/search').replace(
      queryParameters: <String, String>{
        'q': query,
        'page': '$page',
        'sort': sort,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
    );
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('角色卡搜索响应格式不正确');
    return _pageOf(d);
  }

  /// 搜索用户（GET `/api/v1/users/search`）。
  ///
  /// `sort` 取 relevance/new。返回 _user_public + is_following。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  searchUsers(String query, {int page = 1, String sort = 'relevance'}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/users/search',
    ).replace(queryParameters: {'q': query, 'page': '$page', 'sort': sort});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('用户搜索响应格式不正确');
    return _pageOf(d);
  }

  /// 顶栏实时搜索建议（GET `/api/v1/search/suggest`）。
  ///
  /// 返回匹配度最高的角色卡与作者，供输入时下拉展示。
  Future<({List<Map<String, dynamic>> cards, List<Map<String, dynamic>> users})>
  getSearchSuggest(String query) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri(
      '/api/v1/search/suggest',
    ).replace(queryParameters: {'q': query});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('搜索建议响应格式不正确');
    List<Map<String, dynamic>> listOf(Object? raw) {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }

    return (cards: listOf(d['cards']), users: listOf(d['users']));
  }

}
