part of 'client.dart';

/// AUTH 认证 ／ AUTH 认证（服务器地址校验）
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension AuthApi on ApiClient {
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
    final data = await _postJson(
      _apiUri('/api/v1/auth/token'),
      <String, dynamic>{'identifier': identifier, 'password': password},
    );
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
