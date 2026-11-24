import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dna/utils/error_display.dart';

/// 单个对象「加载中 / 成功 / 失败」的统一状态机。
///
/// island 端有 8 个页面各自维护这三件套（`bool _loading` + `String? _error` +
/// `T? _detail`）以及一个 `_load()`，而「刷新时要不要清空旧值」各家还不一样：
/// 有的清空（刷新过程整页变加载态），有的保留（旧内容留着，只更新）。
///
/// 统一到一条语义：**保留旧值**。
///
/// - 首次加载（`value == null`）→ `isLoading == true`，页面显示整页加载态；
/// - 再次刷新 → `isLoading == true` 但 `value` 仍是旧值，页面继续显示旧内容，
///   只在需要的地方显示"正在刷新"的提示（`refreshable` 自己会转圈）；
/// - 失败 → `error` 有值，`value` 保留（页面可选择用旧内容 + 错误条）。
///
/// 这与 [PagedController] 的 `isLoading && items.isEmpty` 直觉一致：**"空"才
/// 意味着"没有东西可显示"，此时才让加载态占满整页。**
class AsyncController<T> extends ChangeNotifier {
  AsyncController(this._fetch);

  final Future<T> Function() _fetch;

  T? _value;
  bool _loading = false;
  String? _error;
  int _requestId = 0;
  bool _disposed = false;

  /// 已加载到的值；首帧或失败且从未成功时为 null。
  T? get value => _value;

  /// `true` 表示已经有过一次成功加载（页面据此区分"空数据"和"还没加载"）。
  bool get hasValue => _value != null;

  /// 正在请求（首次加载与刷新都是 true）。
  bool get isLoading => _loading;

  /// 最近一次失败的原因（成功后清空）。
  String? get error => _error;

  /// 是否该显示整页加载态：**正在加载且还没有任何值可显示**。
  bool get isInitialLoading => _loading && _value == null;

  /// 是否该显示整页错误态：**有错误且没有值可显示**。
  bool get isInitialError => _error != null && _value == null;

  /// 加载（或重新加载）。
  ///
  /// 并发调用只保留最后一次的结果：先发出的请求即使后返回，也不会覆盖新结果。
  Future<void> load() async {
    final int id = ++_requestId;
    _loading = true;
    _error = null;
    _safeNotify();
    try {
      final T next = await _fetch();
      if (_disposed || id != _requestId) return;
      _value = next;
      _error = null;
    } catch (e) {
      if (_disposed || id != _requestId) return;
      _error = describeError(e);
    } finally {
      if (!_disposed && id == _requestId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  /// 直接写入一个外部得到的新值（例如发布/编辑后就地更新，不重新请求）。
  void setValue(T next) {
    _value = next;
    _error = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
