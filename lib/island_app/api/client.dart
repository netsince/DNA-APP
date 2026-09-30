import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:dna/island_app/models/comment.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/utils/points_format.dart';

/// 后端返回的非 2xx 业务错误。
///
/// [message] 为后端 `{"error": ...}` 里的文案（如「找不到该用户名/邮箱」「密码错误」），
/// 可直接展示给用户；[statusCode] 为 HTTP 状态码；[code] 为后端可选的机器可读错误码。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final Object? code;

  @override
  String toString() => message;
}

/// 从非 2xx 响应体里解析后端错误文案；无法解析时回退为「状态码 N」。
ApiException _apiExceptionFrom(int status, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final message = decoded['error'];
      if (message is String && message.trim().isNotEmpty) {
        return ApiException(status, message, code: decoded['code']);
      }
    }
  } catch (_) {
    // 响应体不是 JSON（例如反向代理返回的 HTML 错误页）：忽略，走回退文案。
  }
  return ApiException(status, '状态码 $status');
}

/// 探索角色卡分页结果（items 为卡片摘要 Map）。
typedef ExploreCardsPage = ({
  List<Map<String, dynamic>> items,
  int page,
  int pages,
  int total,
  bool hasNext,
});

/// 探索页热门标签（tag + 卡片数）。
typedef ExploreTag = ({String tag, int count});

/// 探索页元数据（性别列表 + 热门标签）。
typedef ExploreMeta = ({List<String> genders, List<ExploreTag> tags});

/// 通知分页结果（items 为通知摘要 Map）。
typedef NotificationsData = ({
  List<Map<String, dynamic>> items,
  int page,
  int pages,
  int total,
  bool hasNext,
  int unreadCount,
});

/// 积分变化明细分页结果（items 为明细 Map，含 balance）。
typedef PointsData = ({
  List<Map<String, dynamic>> items,
  Decimal balance,
  int page,
  int pages,
  int total,
});

/// 文章分页结果（items 为文章摘要 Map）。
typedef ArticlesData = ({
  List<Map<String, dynamic>> items,
  int page,
  int pages,
  int total,
  bool hasNext,
});

/// 站长推荐结果（items 为 kind:card|user 的 Map）。
typedef RecommendationsData = ({List<Map<String, dynamic>> items});

/// 我的处罚结果（items 为处罚明细 Map）。
typedef PunishmentsData = ({List<Map<String, dynamic>> items});

// =============================================================================
//  ApiClient —— 所有后端接口的唯一调用入口
// =============================================================================
//
//  本文件集中封装 DNAISLAND 后端的全部 HTTP 接口（`/api/v1/*` 与少数公开路径），
//  以方法形式暴露，页面/组件通过 `ApiClient.instance.xxx()` 按需调用。
//
//  ▍统一返回类型约定（见文件内各模块）
//  - 分页列表  → `({List<Map<String,dynamic>> items, int page, int pages, int total, bool hasNext})`
//                （个别带附加字段，如通知 unreadCount / 积分 balance / 话题 topic）
//  - 明细/详情 → `Map<String, dynamic>`（各接口字段不同，调用方各自取值）
//  - 列表      → `List<Map<String, dynamic>>`
//  - 开关操作  → `bool`（是否已开）或 `({bool liked, int count})` 等带状态 record
//  - 写操作    → `Future<void>`（无返回）或返回主键 `int` / `String`
//
//  ▍模块分区（文件内用 `// ====== 分区名 ======` 分隔）
//    AUTH 认证 ｜ SITE 站点/公开 ｜ CARDS 角色卡 ｜ COMMENTS 评论
//    USERS 用户 ｜ MY 我的 ｜ SEARCH 搜索 ｜ TICKETS 工单
//    NOTIFICATIONS 通知 ｜ POINTS 积分 ｜ ARTICLES 文章
//    RECOMMEND&PUNISH 推荐/处罚 ｜ TEAHOUSE 茶馆 ｜ REPORTS 举报
//    PROXY 代理 ｜ IMAGEGEN 生图
//
//  ▍方法 ↔ 后端端点对照表
//  AUTH
//    login(identifier, password)              POST /api/v1/auth/token
//    getMe()                                  GET  /api/v1/auth/me
//    validateServer(rawUrl)                   GET  /api/v1/site-config（校验用）
//  SITE
//    getSiteConfig()                          GET  /api/v1/site-config
//    getSponsors()                            GET  /api/v1/sponsors
//    getStickers()                            GET  /stickers/api
//  CARDS
//    getFeaturedCards()                       GET  /api/v1/cards/featured
//    getSwipeCards()                          GET  /api/v1/cards/swipe
//    getExploreCards()                        GET  /api/v1/cards/explore
//    getExploreMeta()                         GET  /api/v1/cards/explore/meta
//    getCardDetail(cardId)                    GET  /api/v1/cards/<id>
//    searchCards(query)                       GET  /api/v1/cards/search
//    toggleCardLike(cardId)                   POST /api/v1/cards/<id>/like
//    toggleCardFavorite(cardId)               POST /api/v1/cards/<id>/favorite
//    toggleCardHidden(cardId)                 POST /api/v1/cards/<id>/toggle-hidden
//    publishCard(payload)                     POST /api/v1/cards/publish
//    editCard(cardId, payload)                POST /api/v1/cards/<id>/edit
//    resubmitCard(cardId)                     POST /api/v1/cards/<id>/resubmit
//    exportCard(cardId)                       GET  /api/v1/cards/<id>/export
//    parseCardImport(jsonStr)                 POST /api/v1/cards/import/parse
//  COMMENTS
//    getCardComments(cardId)                  GET  /api/v1/cards/<id>/comments
//    postCardComment(cardId, content)         POST /api/v1/cards/<id>/comments
//    toggleCommentLike(cardId, commentId)     POST /api/v1/cards/<id>/comments/<cid>/like
//    toggleCommentPin(cardId, commentId)      POST /api/v1/cards/<id>/comments/<cid>/pin
//    deleteComment(cardId, commentId)         POST /api/v1/cards/<id>/comments/<cid>/delete
//  USERS
//    getUserProfile(username)                 GET  /api/v1/users/<name>
//    getUserComments(username)                GET  /api/v1/users/<name>/comments
//    getFollowers(username)                   GET  /api/v1/users/<name>/followers
//    getFollowing(username)                   GET  /api/v1/users/<name>/following
//    toggleFollow(username)                   POST /api/v1/users/<name>/follow
//    searchUsers(query)                       GET  /api/v1/users/search
//  MY
//    getMyCards()                             GET  /api/v1/my/cards
//    getMyFavorites()                         GET  /api/v1/my/favorites
//    getMyLikes()                             GET  /api/v1/my/likes
//    getMyProfile()                           GET  /api/v1/me/profile
//    updateMyProfile(payload)                 POST /api/v1/me/profile
//  SEARCH
//    getSearchSuggest(query)                  GET  /api/v1/search/suggest
//  TICKETS
//    getTicketCategories()                    GET  /api/v1/tickets/categories
//    getMyTickets()                           GET  /api/v1/tickets
//    createTicket(...)                        POST /api/v1/tickets
//    getTicketDetail(ticketId)                GET  /api/v1/tickets/<id>
//    replyTicket(ticketId, ...)               POST /api/v1/tickets/<id>/reply
//    closeTicket(ticketId)                    POST /api/v1/tickets/<id>/close
//    reopenTicket(ticketId)                   POST /api/v1/tickets/<id>/reopen
//  NOTIFICATIONS
//    getNotifications()                       GET  /api/v1/notifications
//    markAllNotificationsRead()               POST /api/v1/notifications/read-all
//    getUnreadNotificationCount()             GET  /api/v1/notifications/unread-count
//  POINTS
//    getPoints()                              GET  /api/v1/points
//    redeemPoints(codes)                      POST /api/v1/points/redeem
//  ARTICLES
//    getArticles()                            GET  /api/v1/articles
//    getArticleDetail(articleId)              GET  /api/v1/articles/<id>
//  RECOMMEND & PUNISH
//    getRecommendations()                     GET  /api/v1/recommend
//    getPunishments()                         GET  /api/v1/me/punishments
//    submitPunishmentAppeal(id, reason)       POST /api/v1/me/punishments/<id>/appeal
//  TEAHOUSE
//    getTeahousePosts()                       GET  /api/v1/teahouse/posts
//    getTeahousePostDetail(postId)            GET  /api/v1/teahouse/posts/<id>
//    getTeahouseTopics()                      GET  /api/v1/teahouse/topics
//    getTeahouseTopicPosts(topicId)           GET  /api/v1/teahouse/topics/<id>
//    getTeahouseFavorites()                   GET  /api/v1/teahouse/favorites
//    createTeahousePost(...)                  POST /api/v1/teahouse/posts
//    replyTeahousePost(postId, content)       POST /api/v1/teahouse/posts/<id>/reply
//    toggleTeahouseLike(postId)               POST /api/v1/teahouse/posts/<id>/like
//    toggleTeahouseFavorite(postId)           POST /api/v1/teahouse/posts/<id>/favorite
//    editTeahousePost(postId, ...)            POST /api/v1/teahouse/posts/<id>/edit
//    deleteTeahousePost(postId)               POST /api/v1/teahouse/posts/<id>/delete
//    searchTeahousePosts(query)               GET  /api/v1/teahouse/search
//    searchLinkCards(query)                   GET  /api/v1/teahouse/card-search
//  REPORTS
//    getReportReasons()                       GET  /api/v1/reports/meta
//    submitReport(...)                        POST /api/v1/reports
//  PROXY
//    getProxyConfig()                         GET  /api/v1/proxy/config
//    saveProxyConfig(...)                     POST /api/v1/proxy/config
//    resetProxyToken()                        POST /api/v1/proxy/config
//    deleteProxyConfig()                      POST /api/v1/proxy/config
//  IMAGEGEN
//    getImageGenMeta()                        GET  /api/v1/image-gen/meta
//    generateImage(...)                       POST /api/v1/image-gen/generate
//    getActiveImageGenTasks()                 GET  /api/v1/image-gen/tasks
//    getImageGenTaskDetail(taskId)            GET  /api/v1/image-gen/tasks/<id>
//    getImageGenLogs()                        GET  /api/v1/image-gen/logs
// =============================================================================

/// 与 DNAISLAND 后端通信的极简客户端。
///
/// 使用 dart:io 的 HttpClient 并显式设置 connectionTimeout，避免在
/// DNS / TCP 连接阶段挂起时超时（http 包在此场景超时经常不生效）。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const Duration _timeout = Duration(seconds: 10);

  /// 复用的 HttpClient：内部维护连接池与 keep-alive，避免每次请求都重建
  /// DNS / TCP / TLS 连接（无限滚动等高频请求尤其受益）。
  final HttpClient _client = HttpClient()
    ..connectionTimeout = _timeout
    // 连接池空闲超时，配合 keep-alive 复用已有连接。
    ..idleTimeout = const Duration(seconds: 15)
    // 每个主机最大连接数，限制同时发起的并发连接。
    ..maxConnectionsPerHost = 4;

  /// 暴露复用连接池的 HttpClient（供带认证头的图片加载等复用）。
  HttpClient get httpClient => _client;

  /// 当前 JWT（由 [AuthSession] 维护）。非空时所有请求自动带 Bearer 头。
  String? token;

  /// 应用通用请求头（UA + Accept + 可选 Authorization）。
  void _applyHeaders(HttpClientRequest request) {
    // 伪装成浏览器 UA，避免被 Cloudflare 等 CDN 的 Bot 管理静默质询/挂起。
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (compatible; DNAISLANDApp/1.0; +${ServerConfig.defaultBaseUrl})',
    );
    request.headers.set('Accept', 'application/json');
    final t = token;
    if (t != null && t.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $t');
    }
  }

  /// 每个请求的最多尝试次数：首次请求 + 失败后最多重试 3 次。
  static const int _maxAttempts = 4;

  /// 相邻两次尝试之间的等待时长，给瞬时故障恢复留出时间。
  static const Duration _retryDelay = Duration(milliseconds: 400);

  /// 发送 GET 请求并将响应解析为 JSON Map（带自动重试）。
  ///
  /// 出错时自动重试（最多 [_maxAttempts] 次尝试）；任何请求错误都会在控制台
  /// 打印详细日志（方法、完整 URL，以及错误时的状态码/响应体或异常），全部
  /// 重试仍失败后向上抛出由调用方降级处理。
  Future<Map<String, dynamic>> _getJson(Uri target) =>
      _requestJson('GET', target, () async {
        final request = await _client.getUrl(target);
        // headers 必须在写入/发送请求之前设置（发送后即锁定）。
        _applyHeaders(request);
        return request;
      });

  /// 发送 JSON POST 请求并将响应解析为 JSON Map（带自动重试）。
  Future<Map<String, dynamic>> _postJson(
    Uri target,
    Map<String, dynamic> body,
  ) =>
      _requestJson('POST', target, () async {
        final request = await _client.postUrl(target);
        // headers 必须在写入/发送请求之前设置（写入 body 会锁定请求头）。
        _applyHeaders(request);
        // 显式以 UTF-8 写入：HttpClient.write(String) 默认按 latin-1 编码，
        // 中文字符会抛 "Contains invalid characters"。
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.add(utf8.encode(jsonEncode(body)));
        return request;
      });

  /// 统一请求入口：GET/POST 共用，带自动重试。
  ///
  /// 重试策略：
  /// - 网络异常（超时、连接被重置、无法连接、DNS 解析失败、TLS 握手失败）
  ///   与 5xx 服务端错误：自动重试，最多共 [_maxAttempts] 次尝试；
  /// - 4xx 客户端错误（未登录/无权限/资源不存在等）与响应解析错误：
  ///   不重试（重试无意义，只会放大问题）。
  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri target,
    Future<HttpClientRequest> Function() open,
  ) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        // 请求头在 open() 内设置（必须在写入 body 之前）。
        final request = await open().timeout(_timeout);
        final response = await request.close().timeout(_timeout);
        final body = await utf8.decodeStream(response).timeout(_timeout);
        final status = response.statusCode;
        if (status < 200 || status >= 300) {
          if (status >= 500 && attempt < _maxAttempts) {
            _logError(
              method,
              target,
              statusCode: status,
              responseBody: body,
              error: '服务端错误，稍后重试（$attempt/$_maxAttempts）',
            );
            await Future<void>.delayed(_retryDelay);
            continue;
          }
          _logError(
            method,
            target,
            statusCode: status,
            responseBody: body,
          );
          throw _apiExceptionFrom(status, body);
        }
        // 响应体可能很大（含内嵌 base64 头像），在后台 isolate 解析，避免卡 UI。
        final decoded = await compute(jsonDecode, body);
        if (decoded is! Map) {
          _logError(method, target, error: '返回格式不正确，body=$body');
          throw Exception('返回格式不正确');
        }
        return decoded as Map<String, dynamic>;
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          _logError(
            method,
            target,
            error: '请求超时，稍后重试（$attempt/$_maxAttempts）',
          );
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        _logError(method, target, error: '请求超时');
        rethrow;
      } on IOException catch (e) {
        // 连接被重置 / 无法连接 / DNS 解析失败 / TLS 握手失败等网络异常，可重试。
        if (attempt < _maxAttempts) {
          _logError(
            method,
            target,
            error: '$e，稍后重试（$attempt/$_maxAttempts）',
          );
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        _logError(method, target, error: e);
        rethrow;
      } catch (e) {
        // 非 2xx 状态码与格式错误已在 try 内打印过详细日志，这里避免重复。
        if (e is ApiException ||
            (e is Exception && e.toString().startsWith('Exception: '))) {
          rethrow;
        }
        // 其他异常（如 JSON 解析失败、业务错误）不重试。
        _logError(method, target, error: e);
        rethrow;
      }
    }
    throw StateError('不可达：重试循环必须返回或抛出');
  }

  /// 在控制台打印请求错误日志，包含请求方法、完整 URL 与错误详情/响应结果。
  void _logError(
    String method,
    Uri target, {
    int? statusCode,
    String? responseBody,
    Object? error,
  }) {
    final buffer = StringBuffer()
      ..writeln('[API ERROR] $method ${target.toString()}')
      ..writeln('  请求内容: $method ${target.toString()}')
      ..writeln('  响应头 statusCode: ${statusCode ?? (error is TimeoutException ? '超时' : '无')}');
    if (responseBody != null) {
      buffer.writeln('  响应体: $responseBody');
    }
    if (error != null) {
      buffer.writeln('  异常: $error');
    }
    // 错误日志需输出到控制台。
    // ignore: avoid_print
    print(buffer.toString());
  }

  // ========================================================================
  //  SITE 站点 / 公开
  // ========================================================================

  /// 拉取公开站点配置（GET /api/v1/site-config）。
  ///
  /// 未配置服务器地址时抛出异常；网络/解析异常向上抛出由调用方决定降级。
  Future<Map<String, dynamic>> getSiteConfig() async {    final base = await ServerConfig.getBaseUrl();
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
      queryParameters: excludeIds.isEmpty ? null : {
        'exclude': excludeIds.join(','),
      },
    );
    if (base.isEmpty) {
      _logError('GET', uri, error: '未配置服务器地址，无法发起请求');
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(uri);
    final list = data['data'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      return e.map(
        (k, v) => MapEntry(k.toString(), v),
      );
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
      return e.map(
        (k, v) => MapEntry(k.toString(), v),
      );
    }).toList();
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
    final uri = _apiUri('/api/v1/cards/explore')
        .replace(queryParameters: query);
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
  //  REPORTS 举报
  // ========================================================================

  /// 拉取举报原因列表（GET `/api/v1/reports/meta`），返回 `(key, label)`。
  Future<List<({String key, String label})>> getReportReasons() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/reports/meta'));
    final d = data['data'];
    final reasons = d is Map ? d['reasons'] : null;
    if (reasons is! List) return <({String key, String label})>[];
    return reasons.map<({String key, String label})>((r) {
      if (r is List && r.length >= 2) {
        return (key: r[0].toString(), label: r[1].toString());
      }
      return (key: r.toString(), label: r.toString());
    }).toList();
  }

  /// 提交举报（POST `/api/v1/reports`，需登录）。
  Future<void> submitReport({
    required String type,
    required String id,
    required String reason,
    String? detail,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(_apiUri('/api/v1/reports'), <String, dynamic>{
      'type': type,
      'id': id,
      'reason': reason,
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    });
  }

  /// 复制/导出角色卡（GET `/api/v1/cards/<card_id>/export`，需登录）。
  ///
  /// 与网页版共用 `card_export_package`：返回可写入剪贴板的角色卡 JSON 包字符串
  /// （`data['package']` 统一序列化为紧凑 JSON）。未登录（401）或异常时抛错；
  /// 失败不改本地状态，由调用方降级。
  Future<String> exportCard(String cardId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/cards/$cardId/export'));
    final d = data['data'];
    if (d is! Map) throw Exception('复制角色卡响应格式不正确');
    final m = d.map((k, v) => MapEntry(k.toString(), v));
    final package = m['package'];
    if (package == null) throw Exception('复制角色卡内容为空');
    // 对齐网页版剪贴板内容：紧凑 JSON（无缩进）。
    return jsonEncode(package);
  }

  /// 切换角色卡隐藏状态（POST `/api/v1/cards/<card_id>/toggle-hidden`，需登录且为作者）。
  ///
  /// 返回切换后的 `is_hidden`。未登录（401）/ 非作者（404）或异常时抛错。
  Future<bool> toggleCardHidden(String cardId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/toggle-hidden'),
      <String, dynamic>{},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('切换隐藏状态响应格式不正确');
    return d['is_hidden'] == true || d['is_hidden'] == 1;
  }

  /// 置顶 / 取消置顶角色卡（POST `/api/v1/cards/<card_id>/toggle-pin`，需登录且为作者）。
  ///
  /// 返回切换后的 `pinned`。仅「已通过」的卡可置顶，每位作者最多 2 张；
  /// 名额已满或卡未通过时抛错，错误文案由服务端给出（ApiException.message）可直接展示。
  Future<bool> toggleCardPinned(String cardId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/toggle-pin'),
      <String, dynamic>{},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('置顶响应格式不正确');
    return d['pinned'] == true || d['pinned'] == 1;
  }

  /// 发布（新建）角色卡（POST `/api/v1/cards/publish`，需登录）。
  ///
  /// [payload] 字段见后端 `create_card_from_payload`：name/gender/persona/intro/
  /// opening/original_link/cover_focus/seed/author_note/author_note_interval/
  /// tags(list)/dialogue_style(list[{user,assistant}])/images({slot: base64 data url})。
  /// 返回新卡 `id` 与 `status`（pending）。
  Future<({String id, String status})> publishCard(Map<String, dynamic> payload) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/cards/publish'), payload);
    final d = data['data'];
    if (d is! Map) throw Exception('发布角色卡响应格式不正确');
    return (
      id: (d['id'] ?? '').toString(),
      status: (d['status'] ?? 'pending').toString(),
    );
  }

  /// 编辑我的角色卡（POST `/api/v1/cards/<id>/edit`，需登录且为作者）。
  ///
  /// 覆盖式更新，编辑后自动重新提审。返回新 `status`。
  Future<String> editCard(String cardId, Map<String, dynamic> payload) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/edit'),
      payload,
    );
    final d = data['data'];
    if (d is! Map) throw Exception('编辑角色卡响应格式不正确');
    return (d['status'] ?? '').toString();
  }

  /// 重新提审被拒绝的角色卡（POST `/api/v1/cards/<id>/resubmit`，需登录且为作者）。
  Future<String> resubmitCard(String cardId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/resubmit'),
      <String, dynamic>{},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('重新提审响应格式不正确');
    return (d['status'] ?? '').toString();
  }

  /// 解析导出的角色卡 JSON（POST `/api/v1/cards/import/parse`，需登录）。
  ///
  /// 返回可用于发布表单预填的字段；命中版权保护时后端返回 400。
  Future<Map<String, dynamic>> parseCardImport(String jsonStr) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/import/parse'),
      <String, dynamic>{'json': jsonStr},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('解析导入响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  // ========================================================================
  //  COMMENTS 角色卡评论
  // ========================================================================

  /// 拉取角色卡评论列表（GET `/api/v1/cards/<card_id>/comments`）。
  ///
  /// 支持 `sort`（latest/hottest）与 `onlyAuthor`（只看作者）。未配置服务器或异常时抛错。
  Future<CommentPage> getCardComments(
    String cardId, {
    int page = 1,
    String sort = 'latest',
    bool onlyAuthor = false,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final query = <String, String>{
      'page': '$page',
      'sort': sort,
      if (onlyAuthor) 'only_author': '1',
    };
    final uri = _apiUri('/api/v1/cards/$cardId/comments')
        .replace(queryParameters: query);
    final data = await _getJson(uri);
    final d = data['data'] is Map ? data['data'] as Map : data;
    return CommentPage.fromJson(Map<String, dynamic>.from(d));
  }

  /// 发表评论（POST `/api/v1/cards/<card_id>/comments`，需登录）。
  ///
  /// `replyToId` 指定楼中楼回复目标。返回新建评论 id。内容为空/超长由后端校验。
  Future<int> postCardComment(
    String cardId,
    String content, {
    int? replyToId,
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{'content': content};
    if (replyToId != null) body['reply_to_id'] = replyToId;
    if (imageData != null && imageData.isNotEmpty) {
      body['image_data'] = imageData;
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments'),
      body,
    );
    final d = data['data'];
    final rawId = d is Map ? d['id'] : null;
    return rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
  }

  /// 评论点赞/取消（POST `/api/v1/cards/<card_id>/comments/<id>/like`，需登录）。
  ///
  /// 返回切换后的 `(liked, count)`。
  Future<({bool liked, int count})> toggleCommentLike(
    String cardId,
    int commentId,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/like'),
      <String, dynamic>{},
    );
    final d = data['data'];
    final liked = d is Map ? d['liked'] == true : false;
    final count = d is Map
        ? (d['count'] is int ? d['count'] as int : int.tryParse('${d['count']}') ?? 0)
        : 0;
    return (liked: liked, count: count);
  }

  /// 评论置顶/取消置顶（POST `/api/v1/cards/<card_id>/comments/<id>/pin`，仅卡作者）。
  ///
  /// 返回切换后的 `is_pinned`。
  Future<bool> toggleCommentPin(String cardId, int commentId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/pin'),
      <String, dynamic>{},
    );
    final d = data['data'];
    return d is Map ? d['is_pinned'] == true : false;
  }

  /// 删除评论（POST `/api/v1/cards/<card_id>/comments/<id>/delete`，仅评论作者）。
  Future<void> deleteComment(String cardId, int commentId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/cards/$cardId/comments/$commentId/delete'),
      <String, dynamic>{},
    );
  }

  /// 从后端 `data` 解析标准分页结果，返回统一的
  /// `(items, page, pages, total, hasNext)`；字段缺失时给出安全默认值。
  ///
  /// 供各分页方法复用，避免重复写 `items is List ? ... : []` 的解析样板。
  ({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})
      _pageOf(Object? raw) {
    final d = raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    final items = d['items'];
    final list = items is List
        ? items
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
        : <Map<String, dynamic>>[];
    return (
      items: list,
      page: (d['page'] as num?)?.toInt() ?? 1,
      pages: (d['pages'] as num?)?.toInt() ?? 1,
      total: (d['total'] as num?)?.toInt() ?? 0,
      hasNext: d['has_next'] == true,
    );
  }

  Uri _apiUri(String path) {
    // ServerConfig.getBaseUrl 是同步缓存读取（main 启动已预热）。
    final base = ServerConfig.cachedBaseUrl;
    return Uri.parse(base).replace(path: path);
  }

  // ========================================================================
  //  AUTH 认证
  // ========================================================================

  /// 登录：用户名/邮箱 + 密码换 JWT（POST /api/v1/auth/token）。
  ///
  /// 成功返回 `data`（含 token 与 user）；失败抛异常。调用方需处理错误。
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址，无法登录');
    }
    final data =
        await _postJson(_apiUri('/api/v1/auth/token'), <String, dynamic>{
      'identifier': identifier,
      'password': password,
    });
    // 后端统一 {"ok": true, "data": {...}}。
    final d = data['data'];
    if (d is! Map) throw Exception('登录响应格式不正确');
    final m = d.map((k, v) => MapEntry(k.toString(), v));
    final t = m['token'];
    if (t is! String || t.isEmpty) throw Exception('登录响应缺少 token');
    return m;
  }

  /// 拉取当前登录用户信息（GET /api/v1/auth/me，需 Bearer token）。
  Future<Map<String, dynamic>> getMe() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/auth/me'));
    final d = data['data'];
    if (d is! Map) throw Exception('用户信息响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
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
    final uri = _apiUri('/api/v1/users/$username')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/users/$username/comments')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/users/$username/teahouse')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/users/$username/$kind')
        .replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('关注列表响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  // ========================================================================
  //  MY 我的（角色卡 / 收藏 / 点赞 / 资料）
  // ========================================================================

  /// 拉取"我的角色卡"分页列表（GET /api/v1/my/cards，需登录）。
  Future<Map<String, dynamic>> getMyCards({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/my/cards')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/my/favorites')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/my/likes')
        .replace(queryParameters: {'page': '$page'});
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
  Future<Map<String, dynamic>> updateMyProfile(Map<String, dynamic> payload) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/me/profile'), payload);
    final d = data['data'];
    if (d is! Map) throw Exception('更新资料响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  // ========================================================================
  //  TICKETS 工单
  // ========================================================================

  /// 我的工单列表（GET `/api/v1/tickets`，需登录）。
  ///
  /// [status] 取 all/open/replied/closed。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      getMyTickets({int page = 1, String status = 'all'}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/tickets')
        .replace(queryParameters: {'page': '$page', 'status': status});
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
  Future<void> replyTicket(int ticketId, {String content = '', String? imageData}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(_apiUri('/api/v1/tickets/$ticketId/reply'), <String, dynamic>{
      'content': content,
      if (imageData != null && imageData.isNotEmpty) 'image_data': imageData,
    });
  }

  /// 关闭工单（POST `/api/v1/tickets/<id>/close`，需登录）。
  Future<void> closeTicket(int ticketId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(_apiUri('/api/v1/tickets/$ticketId/close'), <String, dynamic>{});
  }

  /// 重新打开工单（POST `/api/v1/tickets/<id>/reopen`，需登录）。
  Future<void> reopenTicket(int ticketId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(_apiUri('/api/v1/tickets/$ticketId/reopen'), <String, dynamic>{});
  }

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
    final uri = _apiUri('/api/v1/notifications')
        .replace(queryParameters: {'page': '$page'});
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
    await _postJson(_apiUri('/api/v1/notifications/read-all'), <String, dynamic>{});
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
    final uri =
        _apiUri('/api/v1/points').replace(queryParameters: {'page': '$page'});
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
    final uri = _apiUri('/api/v1/articles').replace(queryParameters: <String, String>{
      'page': '$page',
      'sort': sort,
      if (query.isNotEmpty) 'q': query,
    });
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

  // ========================================================================
  //  RECOMMEND & PUNISH 站长推荐 / 处罚申诉
  // ========================================================================

  /// 拉取站长推荐（GET `/api/v1/recommend`）。
  Future<RecommendationsData> getRecommendations() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/recommend'));
    final d = data['data'];
    if (d is! Map) throw Exception('站长推荐响应格式不正确');
    return (items: _pageOf(d).items);
  }

  /// 拉取我的处罚（GET `/api/v1/me/punishments`，需登录）。
  Future<PunishmentsData> getPunishments() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/me/punishments'));
    final d = data['data'];
    if (d is! Map) throw Exception('处罚响应格式不正确');
    return (items: _pageOf(d).items);
  }

  /// 对指定处罚提交申诉（POST `/api/v1/me/punishments/<id>/appeal`，需登录）。
  ///
  /// 返回更新后的处罚 Map；失败抛异常。
  Future<Map<String, dynamic>> submitPunishmentAppeal(
    int punishmentId,
    String appealReason,
  ) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/me/punishments/$punishmentId/appeal'),
      <String, dynamic>{'appeal_reason': appealReason},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('申诉响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 兑换积分（POST `/api/v1/points/redeem`，需登录）。
  ///
  /// 返回 results（每码结果含 code/ok/message）、success_count、fail_count；
  /// 限流或失败时抛出异常。
  Future<({List<Map<String, dynamic>> results, int successCount, int failCount})>
      redeemPoints(List<String> codes) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/points/redeem'),
      <String, dynamic>{'codes': codes},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('兑换响应格式不正确');
    final results = d['results'];
    final list = results is List
        ? results.whereType<Map>().map((e) {
            return e.map((k, v) => MapEntry(k.toString(), v));
          }).toList()
        : <Map<String, dynamic>>[];
    return (
      results: list,
      successCount: (d['success_count'] as num?)?.toInt() ?? 0,
      failCount: (d['fail_count'] as num?)?.toInt() ?? 0,
    );
  }

  // ========================================================================
  //  TEAHOUSE 茶馆（Feed / 详情 / 话题 / 收藏 / 发帖 / 回复 / 点赞收藏 / 编辑删除 / 搜索）
  // ========================================================================

  /// 拉取茶馆 Feed（GET `/api/v1/teahouse/posts`）。
  ///
  /// 支持 `sort`（hot/new）与可选 `topicId` 过滤。返回含 items（_teapost_item Map）。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      getTeahousePosts({
    int page = 1,
    String sort = 'hot',
    int? topicId,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final query = <String, String>{
      'page': '$page',
      'sort': sort,
      if (topicId != null) 'topic_id': '$topicId',
    };
    final uri = _apiUri('/api/v1/teahouse/posts').replace(queryParameters: query);
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆 Feed 响应格式不正确');
    return _pageOf(d);
  }

  /// 拉取茶馆帖子详情（GET `/api/v1/teahouse/posts/<id>`）。
  ///
  /// 返回含 post / chain（原帖链）/ replies（分页）。可传 [page]/[sort] 分页回复。
  Future<Map<String, dynamic>> getTeahousePostDetail(
    int postId, {
    int page = 1,
    String sort = 'hot',
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/teahouse/posts/$postId')
        .replace(queryParameters: {'page': '$page', 'sort': sort});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆帖子详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 拉取茶馆热门话题（GET `/api/v1/teahouse/topics`）。
  Future<List<Map<String, dynamic>>> getTeahouseTopics() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/teahouse/topics'));
    final d = data['data'];
    final list = d is List
        ? d.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList()
        : <Map<String, dynamic>>[];
    return list;
  }

  /// 拉取某话题下的帖子（GET `/api/v1/teahouse/topics/<id>`）。
  Future<({Map<String, dynamic>? topic, List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      getTeahouseTopicPosts(int topicId, {int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/teahouse/topics/$topicId')
        .replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('话题帖子响应格式不正确');
    final topicRaw = d['topic'];
    final topic = topicRaw is Map
        ? topicRaw.map((k, v) => MapEntry(k.toString(), v))
        : null;
    final p = _pageOf(d);
    return (
      topic: topic,
      items: p.items,
      page: p.page,
      pages: p.pages,
      total: p.total,
      hasNext: p.hasNext,
    );
  }

  /// 拉取我收藏的茶馆帖子（GET `/api/v1/teahouse/favorites`，需登录）。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      getTeahouseFavorites({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/teahouse/favorites')
        .replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆收藏响应格式不正确');
    return _pageOf(d);
  }

  /// 发布茶馆帖子（POST `/api/v1/teahouse/posts`，需登录）。
  ///
  /// [content] 正文；[cardId] 可选关联角色卡；[imageData] 可选单图 base64 data URL；
  /// [topic] 可选话题名。返回新帖 id。
  Future<int> createTeahousePost({
    required String content,
    String? cardId,
    String? imageData,
    String? topic,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (imageData != null && imageData.isNotEmpty)
        'images': <String>[imageData],
      if (topic != null && topic.isNotEmpty) 'topic': topic,
    };
    final data = await _postJson(_apiUri('/api/v1/teahouse/posts'), body);
    final d = data['data'];
    final id = d is Map ? d['id'] : null;
    return id is int ? id : int.tryParse('$id') ?? 0;
  }

  /// 回复茶馆帖子（POST `/api/v1/teahouse/posts/<id>/reply`，需登录）。
  Future<int> replyTeahousePost(int postId, String content, {String? cardId, String? topic}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
    };
    final data = await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/reply'), body);
    final d = data['data'];
    final id = d is Map ? d['id'] : null;
    return id is int ? id : int.tryParse('$id') ?? 0;
  }

  /// 点赞/取消点赞茶馆帖子（POST `/api/v1/teahouse/posts/<id>/like`，需登录）。
  Future<({bool liked, int count})> toggleTeahouseLike(int postId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/like'), <String, dynamic>{});
    final d = data['data'];
    return (
      liked: d is Map && d['liked'] == true,
      count: d is Map ? (d['count'] is int ? d['count'] as int : int.tryParse('${d['count']}') ?? 0) : 0,
    );
  }

  /// 收藏/取消收藏茶馆帖子（POST `/api/v1/teahouse/posts/<id>/favorite`，需登录）。
  Future<({bool favorited, int count})> toggleTeahouseFavorite(int postId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/favorite'), <String, dynamic>{});
    final d = data['data'];
    return (
      favorited: d is Map && d['favorited'] == true,
      count: d is Map ? (d['count'] is int ? d['count'] as int : int.tryParse('${d['count']}') ?? 0) : 0,
    );
  }

  /// 编辑茶馆帖子（POST `/api/v1/teahouse/posts/<id>/edit`，需登录）。
  ///
  /// [content] 新正文；[cardId] 提供则关联；[cardRemoved] true 则解除关联；
  /// [topic] 提供则设置/清除话题；[imageRemoved] true 则移除配图；
  /// [imageData] 提供则用新图整体替换配图（data URL 图片字符串）。
  Future<void> editTeahousePost(
    int postId, {
    required String content,
    String? cardId,
    bool cardRemoved = false,
    String? topic,
    bool imageRemoved = false,
    String? imageData,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final body = <String, dynamic>{
      'content': content,
      if (cardId != null && cardId.isNotEmpty) 'card_id': cardId,
      if (cardRemoved) 'card_removed': true,
      'topic': ?topic,
      if (imageRemoved) 'image_removed': true,
      if (imageData != null && imageData.isNotEmpty) 'images': [imageData],
    };
    await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/edit'), body);
  }

  /// 删除茶馆帖子（POST `/api/v1/teahouse/posts/<id>/delete`，需登录，作者或超管）。
  Future<void> deleteTeahousePost(int postId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(_apiUri('/api/v1/teahouse/posts/$postId/delete'), <String, dynamic>{});
  }

  // ========================================================================
  //  SEARCH 搜索（卡片 / 用户 / 茶馆帖子 / 联想）
  // ========================================================================

  /// 搜索茶馆帖子（GET `/api/v1/teahouse/search`）。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      searchTeahousePosts(String query, {int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/teahouse/search')
        .replace(queryParameters: {'q': query, 'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('茶馆搜索响应格式不正确');
    return _pageOf(d);
  }

  /// 搜索角色卡（GET `/api/v1/cards/search`）。
  ///
  /// `sort` 取 relevance/hot/new；`tag` 可选标签过滤。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      searchCards(String query, {int page = 1, String sort = 'relevance', String? tag}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/cards/search').replace(queryParameters: <String, String>{
      'q': query,
      'page': '$page',
      'sort': sort,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    });
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('角色卡搜索响应格式不正确');
    return _pageOf(d);
  }

  /// 搜索用户（GET `/api/v1/users/search`）。
  ///
  /// `sort` 取 relevance/new。返回 _user_public + is_following。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      searchUsers(String query, {int page = 1, String sort = 'relevance'}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/users/search')
        .replace(queryParameters: {'q': query, 'page': '$page', 'sort': sort});
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
    final uri = _apiUri('/api/v1/search/suggest')
        .replace(queryParameters: {'q': query});
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

  // ========================================================================
  //  PROXY BYOK 代理转发
  // ========================================================================

  /// 获取 BYOK 代理转发配置（GET `/api/v1/proxy/config`，需登录）。
  ///
  /// 返回 `{configured, upstream_base_url, remark, enabled, token, public_base_url}`。
  Future<Map<String, dynamic>> getProxyConfig() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/proxy/config'));
    final d = data['data'];
    if (d is! Map) throw Exception('代理配置响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 保存/更新 BYOK 代理转发配置（POST `/api/v1/proxy/config`，需登录）。
  ///
  /// [upstreamApiKey] 为空表示保持现有密钥不变（仅编辑时合法）。
  Future<Map<String, dynamic>> saveProxyConfig({
    required String upstreamBaseUrl,
    String upstreamApiKey = '',
    String remark = '',
    bool enabled = true,
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/proxy/config'),
      <String, dynamic>{
        'action': 'save',
        'upstream_base_url': upstreamBaseUrl,
        'upstream_api_key': upstreamApiKey,
        'remark': remark,
        'enabled': enabled,
      },
    );
    final d = data['data'];
    if (d is! Map) throw Exception('保存代理配置响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 重置代理访问令牌（POST `/api/v1/proxy/config` action=reset，需登录）。
  Future<String> resetProxyToken() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/proxy/config'),
      <String, dynamic>{'action': 'reset'},
    );
    final d = data['data'];
    if (d is! Map) throw Exception('重置令牌响应格式不正确');
    return (d['token'] ?? '').toString();
  }

  /// 删除代理转发配置（POST `/api/v1/proxy/config` action=delete，需登录）。
  Future<void> deleteProxyConfig() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    await _postJson(
      _apiUri('/api/v1/proxy/config'),
      <String, dynamic>{'action': 'delete'},
    );
  }

  // ========================================================================
  //  IMAGEGEN 生图工作台
  // ========================================================================

  /// 生图工作台元数据（GET `/api/v1/image-gen/meta`，需登录）。
  ///
  /// 返回 `{models, balance, aspects, max_references, max_count}`。
  Future<Map<String, dynamic>> getImageGenMeta() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/image-gen/meta'));
    final d = data['data'];
    if (d is! Map) throw Exception('生图元数据响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 创建生图任务（POST `/api/v1/image-gen/generate`，需登录）。
  ///
  /// [references] 为参考图列表 `[{filename, mimetype, data_b64}]`。
  Future<int> generateImage({
    required String prompt,
    required int modelId,
    String size = 'auto',
    int count = 1,
    List<Map<String, dynamic>> references = const <Map<String, dynamic>>[],
  }) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _postJson(
      _apiUri('/api/v1/image-gen/generate'),
      <String, dynamic>{
        'prompt': prompt,
        'model_id': modelId,
        'size': size,
        'count': count,
        'references': references,
      },
    );
    final d = data['data'];
    if (d is! Map) throw Exception('生图响应格式不正确');
    final id = d['task_id'];
    return id is num ? id.toInt() : int.tryParse('$id') ?? 0;
  }

  /// 当前用户进行中的生图任务（GET `/api/v1/image-gen/tasks`，需登录）。
  Future<List<Map<String, dynamic>>> getActiveImageGenTasks() async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/image-gen/tasks'));
    final d = data['data'];
    if (d is! Map) throw Exception('生图任务响应格式不正确');
    final tasks = d['tasks'];
    return tasks is List
        ? tasks
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
        : <Map<String, dynamic>>[];
  }

  /// 生图任务详情（GET `/api/v1/image-gen/tasks/<id>`，需登录）。
  Future<Map<String, dynamic>> getImageGenTaskDetail(int taskId) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final data = await _getJson(_apiUri('/api/v1/image-gen/tasks/$taskId'));
    final d = data['data'];
    if (d is! Map) throw Exception('生图任务详情响应格式不正确');
    return d.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 生图历史（GET `/api/v1/image-gen/logs`，需登录）。
  ///
  /// 返回 `{items, page, pages, total, has_next}`。
  Future<({List<Map<String, dynamic>> items, int page, int pages, int total, bool hasNext})>
      getImageGenLogs({int page = 1}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/image-gen/logs')
        .replace(queryParameters: {'page': '$page'});
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('生图历史响应格式不正确');
    return _pageOf(d);
  }

  // ========================================================================
  //  TEAHOUSE 茶馆（发帖/回复时关联卡片搜索）
  // ========================================================================

  /// 发帖时搜索可关联的角色卡（GET `/api/v1/teahouse/card-search`，需登录）。
  ///
  /// 返回卡片摘要（id/name/intro/cover/author）列表，供发帖/回复时关联。
  Future<List<Map<String, dynamic>>> searchLinkCards(String query) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    if (query.trim().isEmpty) return const <Map<String, dynamic>>[];
    final uri = _apiUri('/api/v1/teahouse/card-search')
        .replace(queryParameters: {'q': query});
    final data = await _getJson(uri);
    final d = data['data'];
    final items = d is Map ? d['items'] : null;
    return items is List
        ? items
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
        : <Map<String, dynamic>>[];
  }

  // ========================================================================
  //  AUTH 认证（服务器地址校验）
  // ========================================================================

  /// 校验给定地址是否为可用的 DNAISLAND 服务器。
  ///
  /// 通过向 `<地址>/api/v1/site-config` 发请求，要求返回 HTTP 200 且
  /// 业务层 `ok` 为 true（兼容直接返回配置对象的情况）。
  ///
  /// 返回 `null` 表示有效；否则返回人类可读的错误信息。
  Future<String?> validateServer(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return '请输入服务器地址';

    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '地址必须以 http:// 或 https:// 开头';
    }

    try {
      final data = await _getJson(uri.replace(path: '/api/v1/site-config'));
      final ok = data['ok'];
      // 后端统一带 ok 字段；若没有该字段则视为直接返回的配置对象，兼容接受。
      if (ok is bool && !ok) return '该地址不是有效的 DNAISLAND 服务器';
      return null;
    } on TimeoutException {
      return '连接超时，请检查地址或网络';
    } catch (e) {
      return '无法连接：$e';
    }
  }
}
