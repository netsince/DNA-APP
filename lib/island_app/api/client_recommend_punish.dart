part of 'client.dart';

/// RECOMMEND & PUNISH 站长推荐 / 处罚申诉
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension RecommendPunishApi on ApiClient {
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
  Future<
    ({List<Map<String, dynamic>> results, int successCount, int failCount})
  >
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

}
