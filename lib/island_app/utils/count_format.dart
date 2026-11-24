/// 计数缩写：≥1 万显示 x.x万，≥1 千显示 x.xk，其余取整。
///
/// 这段逻辑原本在 island 端抄了四份（`card_tile`、`card_detail_page` 里两份、
/// `swipe_body`），其中两份接受 `dynamic`（接口字段可能是 num），两份接受 `int`，
/// 千位以下一个用 `toStringAsFixed(0)`、一个用 `'$n'` —— 双精度入参
/// （比如接口给 `999.6`）会被格式化成不同的字符串。
///
/// 统一口径：**一律四舍五入到整数**。计数本来就是整数语义，不该出现 `999.6`
/// 或 `1.0` 这种展示。
String formatCount(num? value) {
  final double n = (value ?? 0).toDouble();
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}
