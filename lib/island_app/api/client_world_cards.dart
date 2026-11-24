part of 'client.dart';

/// WORLD CARDS 世界卡（社区栏目）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension WorldCardsApi on ApiClient {
  // ========================================================================
  //  WORLD CARDS 世界卡（社区栏目）
  // ========================================================================

  /// 世界卡列表（GET /api/v1/worlds）。
  ///
  /// 返回分页对象（items / page / pages / total / has_next）。每一项都**不含
  /// 正文** —— 列表只给元信息（名称/简介/词条数/复制量/标签），正文要靠
  /// [downloadWorldText] 单独取。
  Future<Map<String, dynamic>> getWorlds({
    int page = 1,
    int perPage = 20,
    String query = '',
    String tag = '',
    String sort = 'new',
  }) async {
    final Map<String, String> params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      'sort': sort,
    };
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    if (tag.trim().isNotEmpty) params['tag'] = tag.trim();
    final data = await _getJson(
      _apiUri('/api/v1/worlds').replace(queryParameters: params),
    );
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 世界卡详情（GET `/api/v1/worlds/<id>`）：元信息 + 词条名 + 1 条示例。
  Future<Map<String, dynamic>> getWorldDetail(String id) async {
    final data = await _getJson(_apiUri('/api/v1/worlds/$id'));
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 取世界卡原文（GET `/api/v1/worlds/<id>/export`）。
  ///
  /// **原样返回服务端存的那段文本**，不解析 —— 直接交给
  /// WorldExportImportService.importWorld 即可。服务端在这一步同时记复制统计。
  Future<String> downloadWorldText(String id) {
    final Uri target = _apiUri('/api/v1/worlds/$id/export');
    return _requestBody('GET', target, () async {
      final request = await _client.getUrl(target);
      _applyHeaders(request);
      return request;
    });
  }

  /// 发布世界卡（POST /api/v1/worlds）。
  ///
  /// [rawJson] 是 World.toJson() 的文本，**直接当请求体**发出去；服务端按收到
  /// 的字节原样入库，所以客户端这边也不该先 parse 再 encode。
  Future<Map<String, dynamic>> publishWorld(String rawJson) async {
    final data = await _postRaw(_apiUri('/api/v1/worlds'), rawJson);
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 我发布的世界卡（GET `/api/v1/my/worlds`，需登录）。
  ///
  /// **含待审核 / 已拒绝 / 已下架** —— 作者要看得到自己的全部条目和状态。
  Future<Map<String, dynamic>> getMyWorlds({int page = 1}) async {
    final data = await _getJson(
      _apiUri('/api/v1/my/worlds').replace(queryParameters: {'page': '$page'}),
    );
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 我收藏的世界卡（GET `/api/v1/my/world-favorites`，需登录）。
  Future<Map<String, dynamic>> getMyWorldFavorites({int page = 1}) async {
    final data = await _getJson(
      _apiUri(
        '/api/v1/my/world-favorites',
      ).replace(queryParameters: {'page': '$page'}),
    );
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 世界卡热门标签（GET `/api/v1/worlds/tags`）。
  ///
  /// 返回 `[{tag, count}]`，列表页的筛选条用它 —— 客户端不该自己猜标签，
  /// 也不该把全量世界卡拉下来自己聚合。
  Future<List<({String tag, int count})>> getWorldTags() async {
    final data = await _getJson(_apiUri('/api/v1/worlds/tags'));
    final payload = data['data'];
    if (payload is! Map) return const <({String tag, int count})>[];
    final raw = payload['tags'];
    if (raw is! List) return const <({String tag, int count})>[];
    return raw
        .whereType<Map>()
        .map((Map e) {
          final tag = (e['tag'] ?? '').toString();
          final count = e['count'];
          return (tag: tag, count: count is num ? count.toInt() : 0);
        })
        .where((e) => e.tag.isNotEmpty)
        .toList();
  }

  /// 某个用户发布的世界卡（GET `/api/v1/users/<username>/worlds`）。
  ///
  /// 作者主页的「世界」tab 用；可见性由服务端按「本人 / 他人」分别处理。
  Future<Map<String, dynamic>> getUserWorlds(
    String username, {
    int page = 1,
    int perPage = 12,
  }) async {
    final data = await _getJson(
      _apiUri('/api/v1/users/$username/worlds').replace(
        queryParameters: <String, String>{
          'page': page.toString(),
          'per_page': perPage.toString(),
        },
      ),
    );
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 收藏 / 取消收藏世界卡（POST `/api/v1/worlds/<id>/favorite`，需登录）。
  ///
  /// 返回 {favorited: bool, count: int}。
  Future<Map<String, dynamic>> favoriteWorld(String id) async {
    final Uri target = _apiUri('/api/v1/worlds/$id/favorite');
    final data = await _requestJson('POST', target, () async {
      final request = await _client.postUrl(target);
      _applyHeaders(request);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode('{}'));
      return request;
    });
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 作者取自己的世界卡原文，**用于编辑，不记复制统计**
  /// （GET `/api/v1/worlds/<id>/source`）。
  ///
  /// 不能用 [downloadWorldText]：那是「复制」动作，会 +1 复制量并写一条溯源记录。
  Future<String> getWorldSource(String id) {
    final Uri target = _apiUri('/api/v1/worlds/$id/source');
    return _requestBody('GET', target, () async {
      final request = await _client.getUrl(target);
      _applyHeaders(request);
      return request;
    });
  }

  /// 编辑已发布的世界卡（PUT `/api/v1/worlds/<id>`）。
  ///
  /// [rawJson] 同样是 World.toJson() 的原文，**整份替换**。服务端会把状态打回
  /// 待审核：审核过的是旧内容。
  Future<Map<String, dynamic>> updateWorld(String id, String rawJson) async {
    final Uri target = _apiUri('/api/v1/worlds/$id');
    final data = await _requestJson('PUT', target, () async {
      final request = await _client.putUrl(target);
      _applyHeaders(request);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode(rawJson));
      return request;
    });
    final payload = data['data'];
    return payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  /// 下架 / 恢复自己的世界卡（POST `/api/v1/worlds/<id>/hide`，toggle）。
  Future<bool> hideWorld(String id) async {
    final Uri target = _apiUri('/api/v1/worlds/$id/hide');
    final data = await _requestJson('POST', target, () async {
      final request = await _client.postUrl(target);
      _applyHeaders(request);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode('{}'));
      return request;
    });
    final payload = data['data'];
    return payload is Map && payload['hidden'] == true;
  }

  /// 重新提审（POST `/api/v1/worlds/<id>/resubmit`）。
  Future<void> resubmitWorld(String id) async {
    final Uri target = _apiUri('/api/v1/worlds/$id/resubmit');
    await _requestJson('POST', target, () async {
      final request = await _client.postUrl(target);
      _applyHeaders(request);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.add(utf8.encode('{}'));
      return request;
    });
  }

  /// 撤回自己发布的世界卡（DELETE `/api/v1/worlds/<id>`）。
  Future<void> deleteWorld(String id) async {
    final Uri target = _apiUri('/api/v1/worlds/$id');
    await _requestJson('DELETE', target, () async {
      final request = await _client.deleteUrl(target);
      _applyHeaders(request);
      return request;
    });
  }

  /// 拉取探索角色卡分页（GET `/api/v1/cards/explore`）。
  ///
  /// 支持 [sort]（hot/new/likes）、[gender]、[tag] 筛选，与网页版同一口径。
  Future<ExploreCardsPage> getExploreCards({
    int page = 1,
    String sort = 'hot',
    String gender = '',
    String? tag,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final query = <String, String>{
      'page': '$page',
      'sort': sort,
      if (gender.isNotEmpty) 'gender': gender,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final uri = _apiUri(
      '/api/v1/cards/explore',
    ).replace(queryParameters: query);
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('探索响应格式不正确');
    return _pageOf(d);
  }

  /// 拉取探索页元数据（GET `/api/v1/cards/explore/meta`）。
  ///
  /// 返回可见卡片的性别列表与热门标签（含计数），与网页版同一口径。
  Future<ExploreMeta> getExploreMeta() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/cards/explore/meta'));
    final d = data['data'];
    if (d is! Map) throw Exception('探索元数据响应格式不正确');
    final gendersRaw = d['genders'];
    final genders = gendersRaw is List
        ? gendersRaw.whereType<String>().toList()
        : <String>[];
    final tagsRaw = d['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.whereType<Map>().map((t) {
            final tag = (t['tag'] ?? '').toString();
            final count = (t['count'] as num?)?.toInt() ?? 0;
            return (tag: tag, count: count);
          }).toList()
        : <ExploreTag>[];
    return (genders: genders, tags: tags);
  }

  /// 拉取单张角色卡详情（GET `/api/v1/cards/<card_id>`）。
  ///
  /// 返回 `_card_detail` 的 data（含 name/gender/persona/intro/opening/
  /// tags/dialogue/images/like_count/favorite_count/liked/favorited/author 等）。
  /// 角色卡不存在或无权限访问时抛异常；未配置服务器时也抛错。
  Future<Map<String, dynamic>> getCardDetail(String cardId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/cards/$cardId'));
    final d = data['data'];
    if (d is! Map) throw Exception('角色卡详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 点赞/取消点赞角色卡（POST `/api/v1/cards/<card_id>/like`）。
  ///
  /// 返回 `(liked, count)`；未登录（401）时抛出可读异常。失败不改变本地状态。
  Future<(bool, int)> toggleCardLike(String cardId) =>
      _toggleCardRelation('/api/v1/cards/$cardId/like', 'liked');

  /// 收藏/取消收藏角色卡（POST `/api/v1/cards/<card_id>/favorite`）。
  Future<(bool, int)> toggleCardFavorite(String cardId) =>
      _toggleCardRelation('/api/v1/cards/$cardId/favorite', 'favorited');

  /// 通用「点赞/收藏」开关：POST 后解析 `{ok, data: {<key>: bool, count: int}}`。
  Future<(bool, int)> _toggleCardRelation(String path, String key) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri(path), <String, dynamic>{});
    final d = data['data'];
    if (d is! Map) {
      throw Exception('操作响应格式不正确');
    }
    final m = d.map((k, v) => MapEntry(k.toString(), v));
    return ((m[key] as bool?) ?? false, (m['count'] as num?)?.toInt() ?? 0);
  }

}
