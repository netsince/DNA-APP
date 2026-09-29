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
import 'theme/tokens.dart';
import 'utils/platform_capabilities.dart';
import 'services/startup_update_check.dart';
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

  static const Color _fallbackSeed = AppColors.seed;

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
      theme: _buildTheme(lightColorScheme),
      darkTheme: _buildTheme(darkColorScheme),
      home: AppRoot(controller: widget.controller),
    );
  }

  /// 由配色方案构建完整主题。
  ///
  /// 所有视觉规范集中在此处定义(参见 `DESIGN_SPEC.md`),业务代码不再手写
  /// 卡片圆角/描边/间距,避免同类元素在不同页面长得不一样。
  ///
  /// 字体:内置**思源黑体**(Source Han Sans / Noto Sans SC,Regular 400 +
  /// Medium 500),不依赖系统字体。原因见 `pubspec.yaml` 的 `fonts:` 注释 ——
  /// 内置字体根治了「中英混排跳字体」「假粗」「跨平台不一致」三个问题。
  static ThemeData _buildTheme(ColorScheme cs) {
    final ThemeData base = ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      fontFamily: AppFont.family,
    );
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      fontFamily: AppFont.family,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // 卡片:扁平 + 细描边(全局统一,替代各页面 235 处手写样式)。
      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        shape: AppBorder.cardShape(cs),
        clipBehavior: Clip.antiAlias,
      ),

      // 应用栏:无阴影、左对齐标题。
      appBarTheme: AppBarTheme(
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        centerTitle: false,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),

      // 列表项:保持 Material 默认密度(此前 minVerticalPadding 被设为 8、
      // contentPadding 垂直设为 8,导致侧边栏等列表项间距翻倍、过于松散)。
      listTileTheme: const ListTileThemeData(
        contentPadding: AppInsets.tile,
      ),

      // 输入框:统一圆角与内边距,使用描边风格而非填充。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: AppBorder.card(cs),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: AppBorder.card(cs),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
      ),

      // 分割线:统一颜色。
      dividerTheme: DividerThemeData(
        color: AppBorder.color(cs),
        thickness: 1,
        space: 1,
      ),

      // 提示条:浮动样式,统一圆角。
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
      ),

      // 对话框:统一圆角。
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      // 底部抽屉:统一顶部圆角。
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topRounded),
      ),

      // 弹窗菜单:统一圆角。
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),

      // 文字层级:把 Material 默认字号重映射到项目自己的 6 档字号阶。
      //
      // 默认 M3 的问题:titleLarge=22 被当成卡片小标题用(实际应为 16),
      // 而 14px 上挤了 3 个级别、16→22 之间断层 6px。这里按 AppFontSize
      // 重新映射,保证语义与视觉一一对应(参见 DESIGN_SPEC.md 字号章节)。
      textTheme: _buildTextTheme(base.textTheme),
    );
  }

  /// 按 [AppFontSize] 六档重映射 Material `TextTheme`。
  ///
  /// | 槽位          | 字号 | 用途                       |
  /// |---------------|------|----------------------------|
  /// | `headlineMedium` | 24 | 大标题(启动页、空状态)     |
  /// | `headlineSmall`  | 20 | 页面标题(全屏页、OOBE)     |
  /// | `titleLarge`     | 16 | 小标题(卡片分区)           |
  /// | `titleMedium`    | 16 | 小标题(对话框/列表)        |
  /// | `titleSmall`     | 14 | 强调正文                   |
  /// | `bodyLarge`      | 16 | 大号正文(输入框)           |
  /// | `bodyMedium`     | 14 | 正文(默认)                 |
  /// | `bodySmall`      | 12 | 说明文字                   |
  /// | `labelLarge`     | 14 | 按钮文字                   |
  /// | `labelMedium`    | 12 | 次要标签                   |
  /// | `labelSmall`     | 11 | 极小标注(时间戳、角标)     |
  static TextTheme _buildTextTheme(TextTheme base) {
    // 字重只用 400 / 500(内置字体的两个真实字重),禁止 w600/w700 合成加粗。
    // 行高按中文阅读优化:标题紧凑(1.35)、正文宽松(1.55)。
    const double hTitle = AppLineHeight.title;
    const double hBody = AppLineHeight.body;
    return base.copyWith(
      // 大标题 24
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: AppFontSize.headline,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      // 页面标题 20
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: AppFontSize.title,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      // 小标题 16(此前为 22,是"字号过大"的主因)
      titleLarge: base.titleLarge?.copyWith(
        fontSize: AppFontSize.subtitle,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: AppFontSize.subtitle,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: AppFontSize.body,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      // 正文
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: AppFontSize.subtitle,
        height: hBody,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: AppFontSize.body,
        height: hBody,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: AppFontSize.caption,
        height: hBody,
      ),
      // 标签
      labelLarge: base.labelLarge?.copyWith(
        fontSize: AppFontSize.body,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: AppFontSize.caption,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: AppFontSize.tiny,
        fontWeight: AppWeight.medium,
        height: hTitle,
      ),
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
    // 启动后检查一次更新（可在「高级 → setupdatepage」关闭）。
    // 放在首帧之后发起，不阻塞启动。
    StartupUpdateCheck.schedule(context, widget.controller);
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
                      style: TextStyle(fontSize: AppFontSize.subtitle, fontWeight: AppWeight.medium),
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
              const SizedBox(height: 24),
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
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FitText(title,
                  style: const TextStyle(fontWeight: AppWeight.medium)),
              const SizedBox(height: 2),
              FitText(detail,
                  style: TextStyle(fontSize: AppFontSize.caption, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
