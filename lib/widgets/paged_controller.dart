import 'package:flutter/foundation.dart';

import '../utils/error_display.dart';

/// 一页数据：本页条目 + 还有没有下一页。
@immutable
class PagedResult<T> {
  const PagedResult({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;

  /// 便捷构造：空页（没有更多）。
  static PagedResult<T> empty<T>() => PagedResult<T>(items: <T>[], hasMore: false);
}

/// 取第 [page] 页。页码从 [PagedController.firstPage] 开始。
typedef PagedFetch<T> = Future<PagedResult<T>> Function(int page);

/// 分页列表的**唯一状态机**（全项目共用一个）。
///
/// 以前每个列表页各写一份：
/// ```dart
/// bool _loading = true; bool _loadingMore = false; bool _noMore = false;
/// int _page = 0; String? _error;
/// Future<void> _load({bool reset = false}) async { ... }
/// ```
/// 16 个文件抄了 16 遍，且每遍都各自漂移一点（有的 `_failed`、
/// 有的页码从 1 开始、有的失败时保留旧列表、有的直接清空）。
///
/// 现在统一到这里。页面只需要：
/// ```dart
/// late final PagedController<Map<String, dynamic>> _paged = PagedController(
///   fetch: (page) async {
///     final data = await ApiClient.instance.getMyCards(page: page);
///     return PagedResult(
///       items: ...,
///       hasMore: data['has_next'] == true,
///     );
///   },
///   onChanged: () { if (mounted) setState(() {}); },
///   firstLoadError: '角色卡列表加载失败，请稍后重试',
/// );
/// ```
///
/// 语义（与旧手写实现保持一致，别处不要再自行发挥）：
/// * `load(reset: true)` = 首屏/刷新：清空重来，失败时若列表为空才记错误；
/// * `load()` = 加载更多：`hasMore` 为 false 或正在加载时直接返回（幂等）；
/// * 失败**不清空已有列表**（翻页中途失败，用户还能看已经加载到的内容）；
/// * 同一时刻只允许一个请求在飞；
/// * **异常不吞**：原始异常会进 `error` 文案（首屏）和日志（含翻页失败），
///   `errorObject` 保留异常对象本身。
///
class PagedController<T> {
  PagedController({
    required this.fetch,
    this.firstPage = 1,
    this.onChanged,
    this.firstLoadError = '加载失败，请稍后重试',
  });

  final PagedFetch<T> fetch;

  /// 首页页码（多数接口从 1 开始，个别从 0 开始）。
  final int firstPage;

  /// 状态变化回调（页面通常写 `if (mounted) setState(() {})`）。
  final VoidCallback? onChanged;

  /// 首屏失败时给页面显示的文案（翻页失败不显示这个）。
  final String firstLoadError;

  final List<T> items = <T>[];

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadedOnce = false;
  int _page = 0;
  String? _error;
  Object? _errorObject;
  bool _disposed = false;

  /// 请求在飞时又被要求刷新（比如用户改了排序/搜索词）：记下来，
  /// 等当前请求结束后自动补一次，避免"用户操作被静默丢掉"。
  bool _refreshPending = false;

  /// 列表内容（外部只读）。
  List<T> get list => List<T>.unmodifiable(items);

  /// 首屏/刷新是否正在进行。
  bool get isLoading => _loading;

  /// 是否正在加载下一页。
  bool get isLoadingMore => _loadingMore;

  /// 还有没有下一页。
  bool get hasMore => _hasMore;

  /// 是否至少成功加载过一次（用于区分「首屏加载中」和「真的没数据」）。
  bool get loadedOnce => _loadedOnce;

  /// 首屏错误文案（没有错误时为 null）。
  ///
  /// 里面**带原始异常信息**：宁可让人看到 `Exception: 未配置服务器地址`
  /// 这种原文，也不要换成一个看不出所以然的「加载失败」。见 [errorObject]。
  String? get error => _error;

  /// 最近一次失败的原始异常（首屏或翻页失败都会记；便于日志与排查）。
  Object? get errorObject => _errorObject;

  /// 当前页号（0 = 还没加载过）。
  int get page => _page;

  /// 已经加载过、没在加载、没错误、但没有数据 —— 页面该显示空状态。
  bool get isEmpty => _loadedOnce && !_loading && _error == null && items.isEmpty;

  bool get _busy => _loading || _loadingMore;

  /// 加载一页。
  ///
  /// [reset] 为 true 表示首屏/刷新（从 [firstPage] 重新开始）。
  /// 并发调用会被忽略；`hasMore` 为 false 时加载更多会被忽略。
  Future<void> load({bool reset = false}) async {
    if (_disposed) return;
    if (_busy) {
      if (reset) _refreshPending = true;
      return;
    }
    if (!reset && (!_hasMore || _page == 0)) return;

    final int targetPage = reset ? firstPage : _page + 1;
    if (reset) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    _notify();

    try {
      final PagedResult<T> result = await fetch(targetPage);
      if (_disposed) return;
      if (reset) items.clear();
      items.addAll(result.items);
      _page = targetPage;
      // 与本项目既有语义一致：返回空页也算「没有更多」。
      _hasMore = result.items.isNotEmpty && result.hasMore;
      _loadedOnce = true;
      _error = null;
      _loading = false;
      _loadingMore = false;
      _notify();
    } catch (error, stack) {
      if (_disposed) return;
      _loading = false;
      _loadingMore = false;
      _errorObject = error;
      // **不吞异常**：原文进日志，也进首屏错误文案（翻页失败只进日志，
      // 因为列表还在，界面上不该整页变成错误态）。
      debugPrint('[PagedController] 取第 $targetPage 页失败：${describeError(error)}');
      debugPrintStack(stackTrace: stack as StackTrace?);
      if (items.isEmpty) {
        _error = '$firstLoadError\n${describeError(error)}';
      }
      _notify();
    }
    await _drainPendingRefresh();
  }

  /// 收尾：如果这期间有人要求过刷新，补一次（只补一次，避免抖动）。
  Future<void> _drainPendingRefresh() async {
    if (_disposed || !_refreshPending) return;
    _refreshPending = false;
    await load(reset: true);
  }

  /// 刷新（等价 `load(reset: true)`）。
  Future<void> refresh() => load(reset: true);

  /// 加载更多（等价 `load()`）。
  Future<void> loadMore() => load();

  /// 清空错误（页面在用户点「重试」前想先清一下时用）。
  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    onChanged?.call();
  }

  /// 页面销毁时必须调用：之后所有回调都不再触发。
  void dispose() => _disposed = true;
}
