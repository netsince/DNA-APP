import 'package:dna/island_app/shared_prefs.dart';

/// 服务器地址校验器：返回 null 表示有效，否则返回人类可读错误。
typedef ServerValidator = Future<String?> Function(String url);

/// 持久化管理 DNAISLAND 后端地址。
///
/// DNAISLAND 是开源项目，APP 支持自定义服务器：官方用户开箱即用（直接用
/// [defaultBaseUrl]），自建用户在「设置 → 服务器地址」里改成自己的地址即可。
class ServerConfig {
  static const String _key = 'dnaisland_base_url';

  /// 官方服务器地址（全 App 单点定义）。
  ///
  /// 这里是唯一的官方域名来源：首次启动的默认地址、兜底设置页的预填与「使用官方
  /// 服务器」按钮、请求 User-Agent 都引用它。选它作为默认值的理由：这是社区官方
  /// 站点，官方用户不该被要求手填地址。规范形式不带尾斜杠（见 [normalize]）。
  static const String defaultBaseUrl = 'https://dnaisland.nb6.ltd';

  /// 最近一次读取到的地址（同步读取，供 ApiClient 直接使用）。
  static String _cached = '';

  static String get cachedBaseUrl => _cached;

  /// 是否已经配置过服务器地址。
  ///
  /// 取代了旧的 `dnaisland_oobe_done` 标志：那是一个可以与地址不一致的独立状态源，
  /// 现在「有没有地址」就是唯一真相，少一个能自相矛盾的状态。
  static bool get hasBaseUrl => _cached.isNotEmpty;

  /// 读取已配置的后端地址，未配置时返回空字符串，并缓存到 [cachedBaseUrl]。
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPrefs.instance;
    _cached = prefs.getString(_key) ?? '';
    return _cached;
  }

  /// 保存后端地址（自动规范化）。
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPrefs.instance;
    _cached = normalize(url);
    await prefs.setString(_key, _cached);
  }

  /// 规范化用户输入的地址：去首尾空白、去掉末尾多余的 `/`。
  ///
  /// 去尾斜杠是为了让同一个地址只有一种写法（否则 `https://a.b` 与 `https://a.b/`
  /// 会被当作两个不同的值）。只有协议头的输入（`https://`）不能被削成 `https:`。
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/') && !u.endsWith('://')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 解析相对链接：若以 `/` 开头且非 http(s)，则在前面补上服务器地址；
  /// 否则原样返回（绝对地址、mailto:、空串等）。依赖 [cachedBaseUrl] 已缓存。
  static String resolveUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/') && _cached.isNotEmpty) {
      final base = _cached.endsWith('/')
          ? _cached.substring(0, _cached.length - 1)
          : _cached;
      return '$base$u';
    }
    return u;
  }
}
