import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/app_settings.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';

/// 社区（岛）的**隐藏预热**：把岛的启动初始化与「推荐」首屏数据提前做掉。
///
/// ## 为什么需要它
///
/// 岛原本在自己的 `main.dart` 里启动，合并进主项目后这段初始化被搬到了
/// 「社区」栏目的 [State.initState] 里 —— 于是**点开社区才开始转圈**：
/// 读设置、解析服务器地址、拉站点配置与登录会话、预取表情包，全都在
/// 用户点进去之后才发生，首屏还要再等一次推荐卡片的网络请求。
///
/// 现在改成：主应用**首屏渲染之后**在后台静默把这段初始化跑完，并顺手
/// 预取一批推荐卡片。用户点「社区」时直接就有内容，不再转圈。
///
/// ## 边界
///
/// * **不影响开屏速度**：所有工作都在首帧之后发起，且全是 `await` 的
///   异步 IO（SharedPreferences / HTTP），不占用构建阶段；
/// * **不抢启动资源**：调用方在「开屏动画结束 / 主界面可见」之后才
///   [schedule]，动画期间一个请求都不发；
/// * **关掉社区就不预热**：设置里关闭社区后 [schedule] 直接返回，
///   不读站点配置、不拉推荐，完全当作没有这个功能；
/// * 全程**失败静默**：预热失败不该在主应用里弹任何东西，真正打开社区时
///   各页面自己会重试并显示错误态。
class CommunityPreload {
  CommunityPreload._();

  static final CommunityPreload instance = CommunityPreload._();

  /// 预取数据的保鲜期：在这之内重新进入社区可直接复用，避免刚看过又转圈。
  static const Duration freshFor = Duration(minutes: 2);

  bool _booted = false;
  Future<void>? _booting;
  bool _needsSetup = false;
  String? _setupError;

  List<Map<String, dynamic>>? _featured;
  DateTime? _featuredAt;

  bool _started = false;

  /// 岛的启动初始化是否已完成（读设置 / 服务器地址 / 站点配置 / 登录态 / 表情包）。
  bool get isBooted => _booted;

  /// 是否需要用户先配置服务器地址（官方默认地址也连不上时）。
  bool get needsSetup => _needsSetup;

  /// 服务器校验失败的原因（[needsSetup] 为真时有意义）。
  String? get setupError => _setupError;

  /// 仍在保鲜期内的推荐卡片；没有或已过期返回 `null`（调用方应自己重新拉）。
  List<Map<String, dynamic>>? get freshFeaturedCards {
    final List<Map<String, dynamic>>? cards = _featured;
    final DateTime? at = _featuredAt;
    if (cards == null || at == null) return null;
    if (DateTime.now().difference(at) > freshFor) return null;
    return cards;
  }

  /// 在首屏渲染之后安排一次隐藏预热（幂等：真正开跑只跑一次）。
  ///
  /// [enabled] 在**真正开跑的那一刻**再取一次值：用户在开屏动画期间就把
  /// 社区关掉的话，这里什么都不做，也不占用「已预热」这个位置 —— 之后
  /// 重新打开社区时再调用一次即可正常预热。
  void schedule({required bool Function() enabled}) {
    if (_started) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started || !enabled()) return;
      _started = true;
      unawaited(_warmUp());
    });
  }

  Future<void> _warmUp() async {
    await ensureBooted();
    if (_needsSetup) return;
    await prefetchFeatured();
  }

  /// 跑完岛的启动初始化（幂等；并发调用共享同一次）。
  Future<void> ensureBooted() {
    if (_booted) return Future<void>.value();
    return _booting ??= _boot();
  }

  /// 搬自岛的 `MyApp._init()`：首次启动（尚无地址）时先试官方默认地址，
  /// 校验失败才落到设置页；已配置过的安装不做校验，避免把一次网络抖动
  /// 变成强制设置页。
  ///
  /// 整个预热是**后台任务**：任何一步意外失败都不允许让「社区」永久卡在
  /// 转圈上（[ensureBooted] 的 Future 一旦以失败告终，等它的页面就再也
  /// 醒不过来）。所以失败也照样标记为已初始化，让社区页自己渲染，
  /// 各页面各自重试、各自报错。
  Future<void> _boot() async {
    try {
      await Future.wait(<Future<void>>[
        AppSettings.instance.load(),
        ServerConfig.getBaseUrl(),
      ]);
      if (!ServerConfig.hasBaseUrl) {
        final String? err = await ApiClient.instance.validateServer(
          ServerConfig.defaultBaseUrl,
        );
        if (err == null) {
          await ServerConfig.setBaseUrl(ServerConfig.defaultBaseUrl);
        } else {
          _needsSetup = true;
          _setupError = err;
          return;
        }
      }
      await SiteConfig.instance.load();
      await AuthSession.instance.load();
      // 后台预取表情包目录（公开接口），失败静默回退。
      StickerCatalog.instance.ensureLoaded();
    } catch (_) {
      // 预热失败：不打扰用户，社区页会自己再试。
    } finally {
      _booted = true;
    }
  }

  /// 用户在设置页填完服务器地址后调用：补跑一遍初始化并重新预取。
  Future<void> completeSetup() async {
    _needsSetup = false;
    _setupError = null;
    _booted = true;
    try {
      await SiteConfig.instance.load();
      await AuthSession.instance.load();
      StickerCatalog.instance.ensureLoaded();
    } catch (_) {
      // 同上：填完地址后即使某一步失败也要放行，页面自己会重试。
    }
    await prefetchFeatured();
  }

  /// 预取「推荐」首屏卡片。失败静默：打开社区时首页会自己重试。
  Future<void> prefetchFeatured() async {
    if (_needsSetup) return;
    if (ServerConfig.cachedBaseUrl.isEmpty) return;
    try {
      final List<Map<String, dynamic>> cards =
          await ApiClient.instance.getFeaturedCards();
      _featured = cards;
      _featuredAt = DateTime.now();
    } catch (_) {
      // 预热失败不打扰用户：真正进入社区时首页会重新拉并显示错误态。
    }
  }

  /// 仅测试用：把单例恢复到「什么都没发生」的状态。
  @visibleForTesting
  void resetForTest() {
    _booted = false;
    _booting = null;
    _needsSetup = false;
    _setupError = null;
    _featured = null;
    _featuredAt = null;
    _started = false;
  }

  /// 仅测试用：直接注入预取结果（真实路径只有 [prefetchFeatured] 会写它）。
  @visibleForTesting
  void setFeaturedForTest(
    List<Map<String, dynamic>>? cards, {
    DateTime? fetchedAt,
  }) {
    _featured = cards;
    _featuredAt = fetchedAt ??
        (cards == null ? null : DateTime.now());
  }
}
