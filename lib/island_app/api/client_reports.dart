part of 'client.dart';

/// REPORTS 举报
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension ReportsApi on ApiClient {
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
  Future<({String id, String status})> publishCard(
    Map<String, dynamic> payload,
  ) async {
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

}
