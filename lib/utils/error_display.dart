/// 异常的**可读写法**：保留原文，只去掉 `Exception: ` / `Error: ` 这类前缀噪声。
///
/// 为什么要它：以前失败提示被统一改成「加载失败，请重试」，把真正的原因
/// （未配置服务器地址 / 401 / 格式不对）藏了起来 —— 用户和排查的人都只能靠猜。
/// 现在统一走这里：**人话前缀 + 原始原因**，既不裸奔也不删除信息。
///
/// ```dart
/// catch (e) {
///   _snack('加载失败：${describeError(e)}');
/// }
/// ```
String describeError(Object error) {
  String text = error.toString().trim();
  for (final String p in <String>[
    'Exception: ',
    'Exception:',
    'Error: ',
    'FormatException: ',
    'StateError: ',
  ]) {
    if (text.startsWith(p)) {
      text = text.substring(p.length).trim();
      break;
    }
  }
  // 空异常（比如 `throw ''`）至少给个可读占位，不要变成「失败：」。
  return text.isEmpty ? '未知错误' : text;
}
