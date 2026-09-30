import 'package:shared_preferences/shared_preferences.dart';

/// 岛（DNAISLAND 社区）的服务器地址与登录态。
///
/// **本地为主**：没配服务器、没登录时，主项目的一切本地功能照常；只有岛
/// 相关的入口会提示去配置。所以这里的状态永远是"可选"的，不能让它成为
/// 启动或聊天的前置条件。
class IslandSession {
  IslandSession._();

  /// 与岛客户端保持一致（自建用户可在设置里改）。
  static const String defaultBaseUrl = 'https://dnaisland.nb6.ltd';

  static const String _kBaseUrl = 'island_base_url';
  static const String _kToken = 'island_token';
  static const String _kUsername = 'island_username';
  static const String _kNickname = 'island_nickname';

  static String _baseUrl = defaultBaseUrl;
  static String _token = '';
  static String _username = '';
  static String _nickname = '';

  static String get baseUrl => _baseUrl;
  static String get token => _token;
  static String get username => _username;

  /// 显示名：昵称优先，没有就用用户名。
  static String get displayName => _nickname.isNotEmpty ? _nickname : _username;

  /// 是否登录。决定「发布到岛 / 我的卡片」等入口是否可用。
  static bool get isLoggedIn => _token.isNotEmpty;

  static Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? defaultBaseUrl;
    _token = prefs.getString(_kToken) ?? '';
    _username = prefs.getString(_kUsername) ?? '';
    _nickname = prefs.getString(_kNickname) ?? '';
  }

  /// 保存服务器地址。传空则回到默认地址。
  ///
  /// 去掉末尾斜杠：拼 `/api/v1/...` 时避免出现双斜杠。
  static Future<void> saveServer(String rawUrl) async {
    final String trimmed = rawUrl.trim();
    _baseUrl = trimmed.isEmpty
        ? defaultBaseUrl
        : (trimmed.endsWith('/')
              ? trimmed.substring(0, trimmed.length - 1)
              : trimmed);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, _baseUrl);
  }

  /// 把卡片里的图片路径补成完整 URL。
  ///
  /// 卡片里的图片可能是完整 URL，也可能是服务端相对路径（`/uploads/...`），
  /// 两种都要兜住。
  static String absoluteUrl(String raw) {
    final String value = raw.trim();
    if (value.isEmpty || value.startsWith('http')) {
      return value;
    }
    return value.startsWith('/') ? '$_baseUrl$value' : '$_baseUrl/$value';
  }

  static Future<void> saveLogin({
    required String token,
    required String username,
    String nickname = '',
  }) async {
    _token = token;
    _username = username;
    _nickname = nickname;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUsername, username);
    await prefs.setString(_kNickname, nickname);
  }

  /// 退出登录：只清登录态，**保留服务器地址**（自建用户不用重填）。
  static Future<void> logout() async {
    _token = '';
    _username = '';
    _nickname = '';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUsername);
    await prefs.remove(_kNickname);
  }
}
