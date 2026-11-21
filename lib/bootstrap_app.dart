import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'main.dart';
import 'models/app_settings.dart';
import 'pages/splash/splash_animations.dart';
import 'pages/splash_page.dart';
import 'services/app_icon_service.dart';
import 'services/auto_backup_service.dart';
import 'services/settings_service.dart';
import 'services/web_font_loader.dart';
import 'services/web_utils.dart';
import 'state/app_controller.dart';
import 'theme/tokens.dart';

/// 启动外壳：**先出窗口、先播开场动画，数据在后面并行加载**。
///
/// 以前 `main()` 里 `await controller.initialize()` 之后才 `runApp`，实测窗口要
/// 8.5–9 秒才出现；用户先盯着长时间空窗，然后动画只剩个尾巴。
///
/// 现在：
/// 1. 只读设置（SharedPreferences，几十毫秒）→ 立刻 `runApp` 播开场动画；
/// 2. 同时 `controller.initialize()` 在后台跑；
/// 3. **动画播完 且 数据就绪**，两个条件都满足才切到主界面。
///
/// 之所以不做「淡出交接」：那需要在主界面上再叠一层 MaterialApp 或保留同一棵
/// 开屏子树，两个都会带来新的状态复用问题；开屏结束后硬切一下反而干净。
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  SplashAnimationSpec? _spec;
  bool _splashDone = false;
  bool _initDone = false;

  /// 两个条件都满足才能进主界面。
  bool get _ready {
    final bool splashing = _spec?.enabled ?? false;
    return _initDone && (!splashing || _splashDone);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // 1) 设置先读出来 —— 它决定播哪段动画，而且很快（只读 prefs，不碰数据）。
    try {
      final AppSettings settings = await SettingsService().load();
      if (mounted) {
        setState(() => _spec = splashAnimationById(settings.splashAnimation));
      }
    } catch (e) {
      debugPrint('读设置失败，跳过开场动画: $e');
    }
    // 2) 数据初始化与动画并行。
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.controller.initialize();
    } catch (e) {
      debugPrint('初始化失败（继续进主界面）: $e');
    }
    // 数据好了再做开机后的后台活：每日备份 / Web 专属的图标与字体。
    if (!kIsWeb) {
      unawaited(AutoBackupService.maybeBackup(widget.controller));
    } else {
      unawaited(
        setBrowserFavicon(
          AppIconService.optionForKey(widget.controller.settings.appIcon)
              .assetPath,
        ),
      );
      unawaited(WebFontLoader.load());
    }
    if (mounted) setState(() => _initDone = true);
  }

  void _onSplashDone() {
    if (mounted) setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return DnaApp(controller: widget.controller, skipSplash: true);
    }
    final SplashAnimationSpec? spec = _spec;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
      ),
      home: spec == null || !spec.enabled
          // 设置还没读出来 / 用户关了动画：先铺底色，别闪一下图标。
          ? const ColoredBox(color: AppColors.splashBackground)
          : SplashPage(animation: spec, onComplete: _onSplashDone),
    );
  }
}
