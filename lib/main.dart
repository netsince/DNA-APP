import 'dart:async';

import 'package:flutter/cupertino.dart'; // ignore: unnecessary_import
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'pages/oobe_page.dart';
import 'pages/splash_page.dart';
import 'services/app_icon_service.dart';
import 'services/auto_backup_service.dart';
import 'services/openai_service.dart';
import 'services/settings_service.dart';
import 'services/ta_service.dart';
import 'services/web_font_loader.dart';
import 'services/web_utils.dart';
import 'state/app_controller.dart';
import 'utils/platform_capabilities.dart';
import 'package:dna/widgets/fit_text.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final controller = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
      );
      await controller.initialize();

      // 每日自动备份：首次进入应用时在后台静默执行（失败不影响启动）。
      // Web 无文件系统，跳过。
      if (!kIsWeb) {
        unawaited(AutoBackupService.maybeBackup(controller));
      } else {
        // Web：应用已保存的浏览器标签页图标，并异步加载中文字体。
        unawaited(setBrowserFavicon(
          AppIconService.optionForKey(controller.settings.appIcon).assetPath,
        ));
        unawaited(WebFontLoader.load());
      }

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FitText(
                '发生错误，应用已切换到保护界面。\n${details.exceptionAsString()}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      };

      runApp(DnaApp(controller: controller));
    },
    (Object error, StackTrace stackTrace) {
      debugPrint('Uncaught zone error: $error\n$stackTrace');
    },
  );
}

class DnaApp extends StatefulWidget {
  const DnaApp({super.key, required this.controller});

  final AppController controller;

  static const Color _fallbackSeed = Color(0xFF147B74);

  @override
  State<DnaApp> createState() => _DnaAppState();
}

class _DnaAppState extends State<DnaApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => setState(() {});

  static ThemeMode _resolveThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String accentMode = widget.controller.settings.accentMode;
    final int? customAccentColor = widget.controller.settings.customAccentColor;

    if (accentMode == 'custom') {
      // 自定义：用用户指定颜色作为种子，统一生成整套 Material 3 配色。
      final Color seed = customAccentColor != null
          ? Color(customAccentColor)
          : DnaApp._fallbackSeed;
      final ColorScheme lightColorScheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
      );
      final ColorScheme darkColorScheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      );
      return _buildMaterialApp(lightColorScheme, darkColorScheme);
    }

    // 自动：主界面跟随系统动态取色（Monet），取不到则用默认种子色。
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme lightColorScheme = lightDynamic ??
            ColorScheme.fromSeed(
              seedColor: DnaApp._fallbackSeed,
              brightness: Brightness.light,
            );
        final ColorScheme darkColorScheme = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: DnaApp._fallbackSeed,
              brightness: Brightness.dark,
            );
        return _buildMaterialApp(lightColorScheme, darkColorScheme);
      },
    );
  }

  Widget _buildMaterialApp(
      ColorScheme lightColorScheme, ColorScheme darkColorScheme) {
    return MaterialApp(
      title: 'Duet Nurturing Ally',
      debugShowCheckedModeBanner: false,
      themeMode: _resolveThemeMode(widget.controller.settings.themeMode),
      theme: ThemeData(
        colorScheme: lightColorScheme,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: darkColorScheme,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: AppRoot(controller: widget.controller),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _showSplash = true;
  bool _showHome = false;
  bool _requireAuth = false;
  bool _authPassed = false;
  bool _hasBeenPaused = false;
  DateTime? _pausedTime;

  /// 本次页面加载（冷启动/刷新）已展示过网页版提示。
  /// 刷新页面会重建整个 Dart 应用，static 状态随之重置，
  /// 因此「网页彻底关闭再打开」时仍会再次提示。
  static bool _webNoticeShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showHome = widget.controller.settings.completedOobe;
    // Web 端不支持生物识别，强制关闭启动认证（否则无法进入应用）。
    _requireAuth = PlatformCapabilities.biometricAuthSupported &&
        widget.controller.settings.requireAuthForApp;
    _showSplash = widget.controller.settings.showSplashAnimation;
    widget.controller.addListener(_onControllerChanged);
    // 网页版每次打开页面（冷启动/刷新）只弹一次预览提示。
    if (kIsWeb && !_webNoticeShown) {
      _webNoticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWebNotice();
      });
    }
  }

  void _showWebNotice() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.info_outline,
                      color: Theme.of(sheetContext).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: FitText(
                      '欢迎使用网页版（预览版）',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _WebNoticeItem(
                icon: Icons.cloud_upload_outlined,
                title: '请手动备份数据',
                detail: '网页版数据保存在浏览器中，清理浏览器数据会导致数据丢失。建议在「设置 → 数据管理 → 导出全部数据」中定期手动备份。',
              ),
              const SizedBox(height: 12),
              const _WebNoticeItem(
                icon: Icons.block_outlined,
                title: '部分功能已禁用',
                detail: '语音输入、语音合成、生物识别锁定等功能在网页版中不可用（设置中已置灰）。',
              ),
              const SizedBox(height: 12),
              const _WebNoticeItem(
                icon: Icons.science_outlined,
                title: '预览版',
                detail: '当前为预览版本，功能与体验可能仍在调整，请以实际使用为准。',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const FitText('我知道了'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('Lifecycle: $state, requireAuth: $_requireAuth, authPassed: $_authPassed, hasBeenPaused: $_hasBeenPaused');
    
    if (state == AppLifecycleState.paused) {
      // 记录进入后台的时间
      _pausedTime = DateTime.now();
      _hasBeenPaused = true;
      debugPrint('Lifecycle: App paused at $_pausedTime');
    } else if (state == AppLifecycleState.resumed) {
      // 只有真正从后台切回前台（之前执行过paused）才需要验证
      if (_hasBeenPaused && _requireAuth && _authPassed) {
        debugPrint('Lifecycle: Resumed from background, checking if auth reset needed');
        _hasBeenPaused = false;
        
        // 只有在后台停留超过1秒才需要重新验证（避免快速切换）
        if (_pausedTime != null) {
          final Duration diff = DateTime.now().difference(_pausedTime!);
          debugPrint('Lifecycle: Time in background: ${diff.inSeconds}s');
          if (diff.inSeconds >= 1) {
            debugPrint('Lifecycle: Resetting auth state');
            setState(() => _authPassed = false);
          }
        }
      }
    }
  }

  void _onControllerChanged() {
    final bool newShowHome = widget.controller.settings.completedOobe;
    final bool newRequireAuth = PlatformCapabilities.biometricAuthSupported &&
        widget.controller.settings.requireAuthForApp;
    if ((newShowHome != _showHome || newRequireAuth != _requireAuth) && mounted) {
      setState(() {
        _showHome = newShowHome;
        _requireAuth = newRequireAuth;
      });
    }
  }

  void _onSplashComplete() {
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  void _onAuthPassed() {
    if (mounted) {
      setState(() => _authPassed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果需要验证且未通过，显示验证页面
    if (_requireAuth && !_authPassed && !_showSplash) {
      return AuthPage(
        onAuthPassed: _onAuthPassed,
        requireAuthForApp: _requireAuth,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: _showSplash
          ? SplashPage(
              key: const ValueKey<bool>(true),
              onComplete: _onSplashComplete,
            )
          : IndexedStack(
              key: const ValueKey<bool>(false),
              index: _showHome ? 1 : 0,
              children: <Widget>[
                OobePage(controller: widget.controller),
                HomePage(controller: widget.controller),
              ],
            ),
    );
  }
}

/// 网页版预览提示中的单条说明。
class _WebNoticeItem extends StatelessWidget {
  const _WebNoticeItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FitText(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FitText(detail,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
