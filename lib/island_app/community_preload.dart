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
///   各页面自己会重试并显示错误态；
/// * **失败会补跑**：上一次预热失败（网络抖动）后，下次真正进社区时会
///   静默再试一次，不必重启应用。
class CommunityPreload {
  CommunityPreload._();

  static final CommunityPreload instance = CommunityPreload._();

  /// 预取数据的保鲜期：在这之内重新进入社区可直接复用，避免刚看过又转圈。
  static const Duration freshFor = Duration(minutes: 2);

  bool _booted = false;
  Future<void>? _booting;
  bool _needsSetup = false;
  String? _setupError;

  /// 上一次预热有没有失败过（站点配置 / 登录态 / 推荐首屏任一步）。
  ///
  /// 失败**不代表**不能进社区（社区各页面自己会重试并显示错误态），但用户
  /// 反馈「预加载有时候没成功」—— 所以真正要进社区时（[ensureBooted]）会
  /// 静默补跑一次，把那次网络抖动补回来。
  bool _bootFailed = false;

  /// 补跑是否正在进行（避免重复补跑）。
  bool _retrying = false;

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
      // 不 await：预热是后台任务，不允许阻塞首屏之后的任何一帧。
      unawaited(ensureBooted());
    });
  }

  /// 跑完岛的启动初始化（幂等；并发调用共享同一次）。
  ///
  /// 已经跑完但**上次失败过**的话，这里会顺手静默补跑一次（不阻塞调用方：
  /// 调用方此时已经可以渲染社区了，补跑成功后再由各页面的监听刷新）。
  Future<void> ensureBooted() {
    if (_booted) {
      _retryIfFailed();
      return Future<void>.value();
    }
    return _booting ??= _boot();
  }

  /// 上次预热失败过就补跑一次（后台、静默、失败也不报错）。
  void _retryIfFailed() {
    if (!_bootFailed || _retrying) return;
    _retrying = true;
    unawaited(() async {
      try {
        await _loadSiteConfigAndSession();
        await prefetchFeatured();
      } finally {
        _retrying = false;
      }
    }());
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
      // 「推荐」首屏与站点配置/登录态**互不依赖**：并行发起，谁慢都不拖住
      // 另一个（以前是串行 await，站点配置一慢，推荐就跟着晚到 —— 用户看到
      // 的就是「预加载有时候没成功」）。
      //
      // 注意 [_booted] 只等后者：首页数据没到，岛的首页自己会显示骨架屏，
      // 不该因为预取慢就让整个社区卡在转圈上。
      final Future<bool> featured = prefetchFeatured();
      await _loadSiteConfigAndSession();
      unawaited(featured);
    } catch (_) {
      // 预热失败：不打扰用户，真正进社区时会补跑（见 _retryIfFailed）。
      _bootFailed = true;
    } finally {
      _booted = true;
    }
  }

  /// 站点配置 / 登录态 / 表情包目录。失败记到 [_bootFailed]，等补跑。
  Future<void> _loadSiteConfigAndSession() async {
    try {
      await SiteConfig.instance.load();
      await AuthSession.instance.load();
      // 后台预取表情包目录（公开接口），失败静默回退。
      StickerCatalog.instance.ensureLoaded();
      _bootFailed = false;
    } catch (_) {
      _bootFailed = true;
    }
  }

  /// 用户在设置页填完服务器地址后调用：补跑一遍初始化并重新预取。
  Future<void> completeSetup() async {
    _needsSetup = false;
    _setupError = null;
    _booted = true;
    await _loadSiteConfigAndSession();
    await prefetchFeatured();
  }

  /// 预取「推荐」首屏卡片。
  ///
  /// 返回是否成功；失败静默（打开社区时首页会自己重试）。失败会被记下来，
  /// 下次真正进社区时补跑一次。
  Future<bool> prefetchFeatured() async {
    if (_needsSetup) return false;
    if (ServerConfig.cachedBaseUrl.isEmpty) return false;
    try {
      final List<Map<String, dynamic>> cards = await ApiClient.instance
          .getFeaturedCards();
      _featured = cards;
      _featuredAt = DateTime.now();
      _bootFailed = false;
      return true;
    } catch (_) {
      // 预热失败不打扰用户：真正进入社区时首页会重新拉并显示错误态。
      _bootFailed = true;
      return false;
    }
  }

  /// 仅测试用：把单例恢复到「什么都没发生」的状态。
  @visibleForTesting
  void resetForTest() {
    _booted = false;
    _booting = null;
    _needsSetup = false;
    _setupError = null;
    _bootFailed = false;
    _retrying = false;
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
    _featuredAt = fetchedAt ?? (cards == null ? null : DateTime.now());
  }
}
