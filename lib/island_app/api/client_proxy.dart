part of 'client.dart';

/// PROXY BYOK 代理转发
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension ProxyApi on ApiClient {
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
    final data =
        await _postJson(_apiUri('/api/v1/proxy/config'), <String, dynamic>{
          'action': 'save',
          'upstream_base_url': upstreamBaseUrl,
          'upstream_api_key': upstreamApiKey,
          'remark': remark,
          'enabled': enabled,
        });
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
    await _postJson(_apiUri('/api/v1/proxy/config'), <String, dynamic>{
      'action': 'delete',
    });
  }

}
