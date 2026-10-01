import 'package:dna/island_app/api/client.dart';

/// 把登录异常转成可直接展示给用户的文案。
///
/// 后端已按产品要求区分「找不到该用户名/邮箱」与「密码错误」（以及失败限流文案），
/// 这里必须原样透传 [ApiException.message]，不能再按状态码覆盖成通用提示——
/// 那正是本次要修的问题（旧实现把所有 401 一律显示为「用户名/邮箱或密码错误」）。
String friendlyLoginError(Object e) {
  if (e is ApiException) return e.message;
  final s = e.toString();
  if (s.contains('未配置服务器')) return '未配置服务器地址，请先在设置中填写';
  final msg = s.replaceFirst(RegExp('^[^:]*:'), '').trim();
  return msg.isEmpty ? '登录失败，请重试' : msg;
}
