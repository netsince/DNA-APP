import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'island_session.dart';

/// 岛接口调用失败。带服务端返回的可读信息，便于直接提示用户。
class IslandApiException implements Exception {
  const IslandApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 岛（DNAISLAND 社区）的极简客户端。
///
/// 只覆盖主项目真正需要的几件事：**登录、卡片详情、导出/导入、发布**，
/// 外加拉取卡片立绘。社区信息流那一套（茶馆/通知/积分/工单…）留给岛自己，
/// 不在这里重复实现。
///
/// 本地为主：这个类不持有任何全局状态，地址与 token 都从 [IslandSession]
/// 现取 —— 没登录时只会得到明确的报错，不会影响本地功能。
class IslandApi {
  IslandApi({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 20);

  final http.Client _client;
  final Duration _timeout;

  Uri _uri(String path) => Uri.parse('${IslandSession.baseUrl}$path');

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (IslandSession.token.isNotEmpty)
      'Authorization': 'Bearer ${IslandSession.token}',
  };

  Future<dynamic> _get(String path) async {
    final http.Response res = await _client
        .get(_uri(path), headers: _headers)
        .timeout(_timeout);
    return _unwrap(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final http.Response res = await _client
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return _unwrap(res);
  }

  /// 拆掉后端统一的 `{data: ...}` 外壳，并把非 2xx 变成可读异常。
  dynamic _unwrap(http.Response res) {
    Map<String, dynamic>? json;
    try {
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } catch (_) {
      json = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final String message = (json?['message'] ?? json?['error'] ?? '')
          .toString();
      throw IslandApiException(
        message.isNotEmpty ? message : '请求失败（HTTP ${res.statusCode}）',
      );
    }
    if (json == null) {
      throw const IslandApiException('服务器返回的不是 JSON');
    }
    return json.containsKey('data') ? json['data'] : json;
  }

  static Map<String, dynamic> _asMap(dynamic value) => value is Map
      ? value.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
      : <String, dynamic>{};

  /// 校验服务器地址是否可用（未登录也能调）。
  Future<Map<String, dynamic>> siteConfig() async =>
      _asMap(await _get('/api/v1/site-config'));

  /// 登录；成功后把 token 与用户名写入 [IslandSession]。
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _post('/api/v1/auth/token', <String, dynamic>{
        'identifier': identifier,
        'password': password,
      }),
    );
    final String token = (data['token'] ?? data['access_token'] ?? '')
        .toString();
    if (token.isEmpty) {
      throw const IslandApiException('登录成功但没拿到 token');
    }
    final Map<String, dynamic> user = _asMap(data['user']);
    await IslandSession.saveLogin(
      token: token,
      username: (user['username'] ?? identifier).toString(),
      nickname: (user['nickname'] ?? '').toString(),
    );
  }

  /// 探索卡片（一页）。
  Future<List<Map<String, dynamic>>> exploreCards({
    int page = 1,
    int pageSize = 20,
  }) async {
    final dynamic data = await _get(
      '/api/v1/cards/explore?page=$page&page_size=$pageSize',
    );
    final dynamic raw = data is Map && data.containsKey('items')
        ? data['items']
        : data;
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      for (final dynamic item in raw)
        if (item is Map)
          item.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
    ];
  }

  /// 卡片详情。
  Future<Map<String, dynamic>> cardDetail(String cardId) async =>
      _asMap(await _get('/api/v1/cards/$cardId'));

  /// 导出角色卡：返回与网页版剪贴板一致的紧凑 JSON 包字符串。
  Future<String> exportCard(String cardId) async {
    final Map<String, dynamic> data = _asMap(
      await _get('/api/v1/cards/$cardId/export'),
    );
    final dynamic package = data['package'];
    if (package == null) {
      throw const IslandApiException('复制角色卡内容为空');
    }
    return jsonEncode(package);
  }

  /// 解析导入的角色卡 JSON 包（服务端做校验与字段归一）。
  Future<Map<String, dynamic>> parseCardImport(String jsonStr) async =>
      _asMap(
        await _post('/api/v1/cards/import/parse', <String, dynamic>{
          'json': jsonStr,
        }),
      );

  /// 发布角色卡，返回 (卡片 id, 审核状态)。
  Future<({String id, String status})> publishCard(
    Map<String, dynamic> payload,
  ) async {
    final Map<String, dynamic> data = _asMap(
      await _post('/api/v1/cards/publish', payload),
    );
    return (
      id: (data['id'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
    );
  }

  /// 拉取卡片立绘字节。
  ///
  /// 卡片里的图片既可能是完整 URL，也可能是服务端相对路径，这里都兜住。
  /// **失败返回 null**：导入时少一张立绘不该让整次导入失败。
  Future<Uint8List?> tryFetchImage(String urlOrPath) async {
    final String raw = urlOrPath.trim();
    if (raw.isEmpty) {
      return null;
    }
    final Uri? uri = raw.startsWith('http')
        ? Uri.tryParse(raw)
        : Uri.tryParse('${IslandSession.baseUrl}$raw');
    if (uri == null) {
      return null;
    }
    try {
      final http.Response res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
