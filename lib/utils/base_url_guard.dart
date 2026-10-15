/// Base URL 的**格式**校验（不联网）。
///
/// 只拦最容易被漏掉、也最容易自己发现的错误：漏了协议头、协议头写错、
/// 或者填了明显不是地址的东西。真正的连通性仍由「保存并检测」负责 ——
/// 这一层的作用是把「等一轮网络往返才知道自己少打了 https://」变成即时反馈。
///
/// 返回 null 表示格式没问题（空字符串也算「没填」，由调用方决定怎么提示）。
String? baseUrlFormatError(String url) {
  final String value = url.trim();
  if (value.isEmpty) return null;

  final Uri? uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '地址要以 http:// 或 https:// 开头，例如 https://api.example.com/v1';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '只支持 http:// 与 https:// 两种协议。';
  }
  return null;
}
