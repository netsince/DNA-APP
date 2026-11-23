import 'package:flutter/widgets.dart';

/// 编辑器表单的**草稿**：文本用控制器（保住输入与光标），选择用字符串/集合。
///
/// 为什么不用 `settings_spec` 那套：设置是「改了就落盘」，编辑器是
/// 「草稿 + 显式保存 + 就地校验」。两套写通道不一样，硬套会让设置侧
/// 多出一层草稿、编辑器就多出一层 patch。
///
/// 用法：页面持有 `FormDraft`，字段用 [FormFields] 里的构件渲染，
/// 保存时读 `draft.text(id)` / `draft.selection(id)`，
/// 校验用 [validateRequired]（把错误落到字段上，不是弹 snackbar）。
class FormDraft {
  FormDraft({
    List<String> textFields = const <String>[],
    List<String> multiFields = const <String>[],
  }) {
    for (final String id in textFields) {
      _controllers[id] = TextEditingController();
    }
    for (final String id in multiFields) {
      _multi[id] = <String>{};
    }
  }

  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, String?> _single = <String, String?>{};
  final Map<String, Set<String>> _multi = <String, Set<String>>{};
  final Map<String, String> _errors = <String, String>{};

  /// 某个文本字段的控制器（渲染 TextField 用；不要自己再 new 一个）。
  TextEditingController controller(String id) {
    final TextEditingController? c = _controllers[id];
    if (c == null) {
      throw ArgumentError('FormDraft: 文本字段 "$id" 没有在构造时登记');
    }
    return c;
  }

  /// 文本值（已 trim）。
  String text(String id) => (_controllers[id]?.text ?? '').trim();

  /// 原始文本（不 trim，写入模型前一般用 [text]）。
  String rawText(String id) => _controllers[id]?.text ?? '';

  /// 单选值（未选为 null）。
  String? selection(String id) => _single[id];

  /// 多选值。
  Set<String> multiSelection(String id) =>
      Set<String>.unmodifiable(_multi[id] ?? const <String>{});

  void select(String id, String? value) {
    _single[id] = (value == null || value.isEmpty) ? null : value;
  }

  void setSingleRaw(String id, String? value) => _single[id] = value;

  void toggleMulti(String id, String value) {
    final Set<String> set = _multi.putIfAbsent(id, () => <String>{});
    if (!set.remove(value)) set.add(value);
  }

  void setMulti(String id, Iterable<String> values) {
    _multi[id] = <String>{...values};
  }

  /// 字段当前的错误文案。
  String? error(String id) => _errors[id];

  void setError(String id, String message) => _errors[id] = message;

  void clearError(String id) => _errors.remove(id);

  void clearAllErrors() => _errors.clear();

  /// 必填校验：把错误落到字段上，返回是否全部通过。
  ///
  /// [rules] 里每条是 `(字段 id, 错误文案)`；**只校验传入的规则**，
  /// 所以「按类型条件隐藏的字段」不会误报。
  bool validateRequired(List<(String, String)> rules) {
    bool ok = true;
    for (final (String id, String message) in rules) {
      final bool empty = selection(id) == null && text(id).isEmpty;
      if (empty) {
        _errors[id] = message;
        ok = false;
      } else {
        _errors.remove(id);
      }
    }
    if (!ok) notifyControllers();
    return ok;
  }

  /// 第一个出错字段的 id（页面按它把视口带回该字段）。
  String? get firstErrorId =>
      _errors.isEmpty ? null : _errors.keys.first;

  /// 文本改动后触发重建：页面在 `onChanged` 里调 `setState` 即可，
  /// 这个方法是给「在校验后想让依赖错误文案的控件刷新」的场景留的钩子。
  void notifyControllers() {
    for (final TextEditingController c in _controllers.values) {
      // 只用于触发依赖它的 widget 重建（空实现也足够，保留语义）。
      c.value = c.value;
    }
  }

  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }
}
