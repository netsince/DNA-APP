import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:dna/island_app/models/comment.dart';
import 'package:dna/island_app/server_config.dart';

import 'package:dna/island_app/utils/points_format.dart';

part 'client_site.dart';
part 'client_cards.dart';
part 'client_world_cards.dart';
part 'client_users.dart';
part 'client_reports.dart';
part 'client_comments.dart';
part 'client_auth.dart';
part 'client_my.dart';
part 'client_tickets.dart';
part 'client_notifications.dart';
part 'client_points.dart';
part 'client_articles.dart';
part 'client_recommend_punish.dart';
part 'client_teahouse.dart';
part 'client_search.dart';
part 'client_proxy.dart';
part 'client_imagegen.dart';

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

  /// 测试注入点：非 null 时**所有 JSON 请求**都走它，不碰真实网络。
  ///
  /// 只为 widget 测试构造「有数据 / 空 / 失败」三种状态；生产路径永远为 null。
  /// 注意它在 [_apiUri] 之后生效，所以测试里仍需先配好 base url。
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String method, Uri uri)?
  debugJsonHandler;

  /// 建立连接（DNS + TCP + TLS）的超时。
  ///
  /// 比响应/正文宽松：debug 构建的冷启动（首次执行的 JIT 编译）本身就要几秒，
  /// 而那段编译时间也会计入墙钟。10 秒会把冷启动的第一次请求直接砍掉。
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// 等响应头 / 等正文首包的超时。
  static const Duration _responseTimeout = Duration(seconds: 15);

  /// 读响应体的超时。
  ///
  /// 推荐流一页就有 160–230KB，跟"等首包"共用一个额度太紧，单独放宽。
  static const Duration _bodyTimeout = Duration(seconds: 30);

  /// 复用的 HttpClient：内部维护连接池与 keep-alive，避免每次请求都重建
  /// DNS / TCP / TLS 连接（无限滚动等高频请求尤其受益）。
  final HttpClient _client = HttpClient()
    ..connectionTimeout = _connectTimeout
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
  ) => _requestJson('POST', target, () async {
    final request = await _client.postUrl(target);
    // headers 必须在写入/发送请求之前设置（写入 body 会锁定请求头）。
    _applyHeaders(request);
    // 显式以 UTF-8 写入：HttpClient.write(String) 默认按 latin-1 编码，
    // 中文字符会抛 "Contains invalid characters"。
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.add(utf8.encode(jsonEncode(body)));
    return request;
  });

  /// 发送**原文** POST（请求体已经是 JSON 文本，不再 jsonEncode 一层）。
  ///
  /// 世界卡的发布就是这样：把 World.toJson() 的文本直接当请求体发出去，
  /// 免得把几百 KB 的文本再转义一遍。
  Future<Map<String, dynamic>> _postRaw(Uri target, String text) =>
      _requestJson('POST', target, () async {
        final request = await _client.postUrl(target);
        _applyHeaders(request);
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.add(utf8.encode(text));
        return request;
      });

  /// 统一请求入口：GET/POST 共用，带自动重试。
  ///
  /// 重试策略：
  /// - 连接类异常（连接被重置、无法连接、DNS 解析失败、TLS 握手失败）与
  ///   5xx 服务端错误：自动重试，最多共 [_maxAttempts] 次尝试；
  /// - **超时不重试**（见下方 on TimeoutException）；
  /// - 4xx 客户端错误（未登录/无权限/资源不存在等）与响应解析错误：
  ///   不重试（重试无意义，只会放大问题）。
  ///
  /// 成功后返回**响应体原文**：JSON 接口由 [_requestJson] 再解析一层；需要
  /// 原文的接口（取世界卡）直接用它 —— 两者共用同一套重试/中止语义。
  Future<String> _requestBody(
    String method,
    Uri target,
    Future<HttpClientRequest> Function() open,
  ) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      HttpClientRequest? request;
      try {
        // 请求头在 open() 内设置（必须在写入 body 之前）。
        request = await open().timeout(_connectTimeout);
        final response = await request.close().timeout(_responseTimeout);
        final body = await utf8.decodeStream(response).timeout(_bodyTimeout);
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
          _logError(method, target, statusCode: status, responseBody: body);
          throw _apiExceptionFrom(status, body);
        }
        return body;
      } on TimeoutException {
        // 超时**必须主动中止**，且**不重试**。
        //
        // 中止：.timeout() 只让 Future 报错，底层连接会继续挂着。配合
        // maxConnectionsPerHost 的上限，几个超时请求就能把连接池占满，
        // 之后每个请求都排队、都超时 —— 表现为「疯狂地无法连接」。
        //
        // 不重试：超时无法判断服务端是否已经处理过，重试 POST 会重复提交
        // （发帖发两遍、导入导两次）；而且每个请求 4 次 × 15 秒地占着连接，
        // 正是把连接池拖死的放大器。读操作的韧性交给调用方的刷新/重进。
        _abort(request);
        _logError(method, target, error: '请求超时');
        rethrow;
      } on IOException catch (e) {
        // 连接被重置 / 无法连接 / DNS 解析失败 / TLS 握手失败等网络异常，可重试
        // —— 这些情况下请求确定没有送达服务端，重试是安全的。
        _abort(request);
        if (attempt < _maxAttempts) {
          _logError(method, target, error: '$e，稍后重试（$attempt/$_maxAttempts）');
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

  /// 统一请求入口：GET/POST 共用，带自动重试；返回解析后的 JSON 对象。
  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri target,
    Future<HttpClientRequest> Function() open,
  ) async {
    final Future<Map<String, dynamic>> Function(String, Uri)? handler =
        debugJsonHandler;
    if (handler != null) {
      return handler(method, target);
    }
    final body = await _requestBody(method, target, open);
    // 响应体可能很大（含内嵌 base64 头像），在后台 isolate 解析，避免卡 UI。
    final decoded = await compute(jsonDecode, body);
    if (decoded is! Map) {
      _logError(method, target, error: '返回格式不正确，body=$body');
      throw Exception('返回格式不正确');
    }
    return decoded as Map<String, dynamic>;
  }

  /// 主动中止请求，把它占用的连接还回连接池。
  ///
  /// 超时/出错后必须调用：否则那条连接会一直挂到服务端或系统超时为止，
  /// 而 [HttpClient.maxConnectionsPerHost] 是硬上限，几个泄漏就能让后续
  /// 所有请求排队等死。
  void _abort(HttpClientRequest? request) {
    if (request == null) return;
    try {
      request.abort();
    } catch (_) {
      // 已结束的请求再 abort 会抛异常，忽略即可。
    }
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
      ..writeln(
        '  响应头 statusCode: ${statusCode ?? (error is TimeoutException ? '超时' : '无')}',
      );
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

}
