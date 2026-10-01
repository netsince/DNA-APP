import 'package:flutter/foundation.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/shared_prefs.dart';
import 'package:dna/island_app/utils/login_error.dart';

/// 登录会话管理：维护 JWT 与当前用户信息，负责登录 / 登出 / 启动恢复。
///
/// 登录成功后把 token 持久化到本地（SharedPreferences），并同步给
/// [ApiClient.token]，后续请求自动携带 `Authorization: Bearer <token>`。
class AuthSession extends ChangeNotifier {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  /// 「去登录」请求信号：每次需要跳转到登录页时自增，外壳监听到后切到「我」页。
  /// 由 [AuthGuard] 触发。
  final ValueNotifier<int> loginRequest = ValueNotifier<int>(0);

  static const String _tokenKey = 'auth_token';

  String? _token;
  Map<String, dynamic>? _user;
  bool _restoring = false;
  bool _busy = false;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  /// 显示名：昵称优先，其次用户名。侧栏/底栏直接用。
  String get displayName {
    if (_user == null) return '';
    final nickname = (_user!['nickname'] ?? '').toString();
    if (nickname.isNotEmpty) return nickname;
    return (_user!['username'] ?? '').toString();
  }

  /// 当前用户头像（服务端路径或 data URL；空串 = 无头像）。侧栏/底栏直接用。
  String get avatar => _user == null ? '' : (_user!['avatar'] ?? '').toString();

  /// 正在恢复会话（启动时静默校验）。
  bool get restoring => _restoring;

  /// 登录请求进行中。
  bool get busy => _busy;

  /// 启动时从本地恢复会话并校验 token 有效性。
  Future<void> load() async {
    final prefs = await SharedPrefs.instance;
    _token = prefs.getString(_tokenKey) ?? '';
    if (_token == null || _token!.isEmpty) {
      _token = null;
      notifyListeners();
      return;
    }
    ApiClient.instance.token = _token;
    _restoring = true;
    notifyListeners();
    // 尝试拉取用户信息；token 无效/过期则清除本地会话。
    try {
      _user = await ApiClient.instance.getMe();
    } catch (_) {
      _token = null;
      _user = null;
      ApiClient.instance.token = null;
      await prefs.remove(_tokenKey);
    }
    _restoring = false;
    notifyListeners();
  }

  /// 登录。成功返回 `null`，失败返回人类可读的错误信息。
  Future<String?> login(String identifier, String password) async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      final data = await ApiClient.instance.login(identifier, password);
      _token = (data['token'] as String?) ?? '';
      _user = data['user'] is Map
          ? (data['user'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : null;
      if (_token!.isEmpty) return '登录响应缺少 token';
      ApiClient.instance.token = _token;
      final prefs = await SharedPrefs.instance;
      await prefs.setString(_tokenKey, _token!);
      return null;
    } catch (e) {
      return friendlyLoginError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 退出登录。
  Future<void> logout() async {
    _token = null;
    _user = null;
    ApiClient.instance.token = null;
    final prefs = await SharedPrefs.instance;
    await prefs.remove(_tokenKey);
    notifyListeners();
  }

}
