import 'package:decimal/decimal.dart';

/// 积分格式化工具：把 [Decimal] 积分渲染为规范字符串。
///
/// 积分精度为 10 位小数（后端 DECIMAL(30,10)），API 以 JSON string 传输。
/// 规范形式（与后端契约一致）：
/// - 不使用指数记号；
/// - 去掉小数末尾多余的 0；
/// - 整数不带小数点；
/// - `-0` 归一为 `0`。
///
/// 这里不依赖 [Decimal.toString] 的默认实现：整数走 [Decimal.toBigInt]，
/// 小数用 `toStringAsFixed(scale)`（与真实 scale 相等，无损）后再手工去尾零，
/// 因此对任意输入都输出规范形式。
String formatPoints(Decimal? value) {
  final v = value ?? Decimal.zero;
  if (v == Decimal.zero) return '0';
  if (v.isInteger) return v.toBigInt().toString();
  var s = v.toStringAsFixed(v.scale);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s.isEmpty ? '0' : s;
}

/// 把 API 返回的积分数值解析为 [Decimal]。
///
/// - `String`：`Decimal.parse`（后端契约：JSON string）；
/// - `num`：`Decimal.parse(v.toString())`（兼容旧数据/内部计算）；
/// - `Decimal`：原样返回；
/// - `null` 或非法值：`Decimal.zero`。
Decimal parsePoints(Object? value) {
  if (value == null) return Decimal.zero;
  if (value is Decimal) return value;
  if (value is String) {
    return Decimal.tryParse(value.trim()) ?? Decimal.zero;
  }
  if (value is num) {
    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }
  return Decimal.zero;
}
