part of 'client.dart';

/// IMAGEGEN 生图工作台
///
/// 从 `client.dart` 拆出：这一组接口只碰一个业务域，拆开之后文件不再是
/// 两千多行的单一类，改动某个域时不用在同一屏里翻 94 个方法。
extension ImagegenApi on ApiClient {
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
  ///
  /// 默认只返回**有产出图**的记录，服务端在 SQL 里过滤完再分页（total/pages 也只数这些）。
  /// 所以瀑布流直接用默认分页即可：哪怕最新的几十条全是失败记录，第 1 页也一定是有图的那些。
  ///
  /// [status] 按状态过滤（`success` / `partial` / `failed`）。传 `failed` 时服务端只返回
  /// 失败记录 —— 「生成失败记录」页用它翻页，否则得先翻过一堆成功记录才凑得齐失败的那些。
  ///
  /// 没有 `include_failed` 开关：把失败记录混进瀑布流会让「最新一页全是失败」的用户
  /// 整页看不到图（曾经的线上事故），失败记录一律走 [status] 那条路单独翻页。
  Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })
  >
  getImageGenLogs({int page = 1, String? status}) async {
    if (ServerConfig.cachedBaseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    final uri = _apiUri('/api/v1/image-gen/logs').replace(
      queryParameters: {
        'page': '$page',
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final data = await _getJson(uri);
    final d = data['data'];
    if (d is! Map) throw Exception('生图历史响应格式不正确');
    return _pageOf(d);
  }

}
