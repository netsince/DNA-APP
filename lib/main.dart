import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart'; // ignore: unnecessary_import
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'pages/auth_page.dart';
import 'pages/chat_page.dart';
import 'state/app_controller.dart';
import 'theme/app_palette.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/animated_font_scale.dart';
import 'theme/tokens.dart';
import 'utils/platform_capabilities.dart';
import 'island_app/community_preload.dart';
import 'pages/oobe_page.dart';
import 'pages/splash_page.dart';
import 'services/resume_service.dart';
import 'utils/ui_feedback.dart';
import 'widgets/app_section.dart';
import 'services/app_icon_service.dart';
import 'services/auto_backup_service.dart';
import 'services/openai_service.dart';
import 'services/settings_service.dart';
import 'services/ta_service.dart';
import 'services/web_font_loader.dart';
import 'services/web_utils.dart';
import 'services/startup_update_check.dart';
import 'services/cloud_tts_selftest.dart';
import 'services/stt_selftest.dart';
import 'services/boot_trace.dart';
import 'services/cloud_tts_service.dart';
import 'package:dna/widgets/fit_text.dart';

Future<void> main() async {

  runZonedGuarded(
    () async {
      BootTrace.mark('start');
      WidgetsFlutterBinding.ensureInitialized();
      BootTrace.mark('binding');
      // 图片缓存上限：默认值（1000 张 / 100MB）对聊天场景偏大，
      // 收窄到 240 张 / 96MB，减少长时间使用后的内存与显存占用。
      PaintingBinding.instance.imageCache
        ..maximumSize = 240
        ..maximumSizeBytes = 96 << 20;
      _installCrashLog();
      // 帧耗时采样（可选）：DNA_FRAME_LOG=1 时把每帧 build/raster 毫秒追加到
      // %TEMP%\dna_frames.log，用来客观判断"滑动/切换卡不卡"，而不是靠感觉。
      if (Platform.environment['DNA_FRAME_LOG'] == '1') {
        final File frameLog = File(
          '${Directory.systemTemp.path}\\dna_frames.log',
        );
        try {
          frameLog.writeAsStringSync('', flush: true);
        } catch (_) {}
        // 首帧之后把视口参数也记一行：判断"到底是逻辑尺寸被放大还是
        // 真的画得很慢"，DPR 与物理尺寸是关键。
        SchedulerBinding.instance.addPostFrameCallback((_) {
          try {
            final ui.FlutterView view =
                WidgetsBinding.instance.platformDispatcher.views.first;
            frameLog.writeAsStringSync(
              'viewport physical=${view.physicalSize.width}x'
              '${view.physicalSize.height} dpr=${view.devicePixelRatio}\n',
              mode: FileMode.append,
              flush: true,
            );
          } catch (_) {}
        });
        SchedulerBinding.instance.addTimingsCallback((
          List<FrameTiming> timings,
        ) {
          final StringBuffer sb = StringBuffer();
          for (final FrameTiming t in timings) {
            sb.writeln(
              '${DateTime.now().toIso8601String()} '
              'build=${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
              'raster=${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
              'total=${(t.totalSpan.inMicroseconds / 1000).toStringAsFixed(1)}',
            );
          }
          try {
            frameLog.writeAsStringSync(
              sb.toString(),
              mode: FileMode.append,
              flush: true,
            );
          } catch (_) {}
        });
      }
      // 云端语音合成开关要尽早加载：聊天页首帧就据此决定是否显示朗读按钮。
      await CloudTtsService.instance.load();
      BootTrace.mark('cloudtts');
      // 自检钩子：仅在 DNA_TTS_SELFTEST 环境变量存在时运行。
      unawaited(CloudTtsSelfTest.runIfRequested());
      unawaited(SttSelfTest.runIfRequested());

      final controller = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
      );
      await controller.initialize();
      BootTrace.mark('controller');

      // 每日自动备份：首次进入应用时在后台静默执行（失败不影响启动）。
      // Web 无文件系统，跳过。
      if (!kIsWeb) {
        unawaited(AutoBackupService.maybeBackup(controller));
      } else {
        // Web：应用已保存的浏览器标签页图标，并异步加载中文字体。
        unawaited(
          setBrowserFavicon(
            AppIconService.optionForKey(controller.settings.appIcon).assetPath,
          ),
        );
        unawaited(WebFontLoader.load());
      }

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
      WidgetsBinding.instance.addPostFrameCallback((_) => BootTrace.mark('firstFrame'));
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
    // 先把自定义界面配色写进全局表面令牌，再据此构建 ThemeData。
    final settings = widget.controller.settings;
    AppPalette.resolve(
      key: settings.paletteKey,
      customCanvas: settings.customCanvasColor,
      customGlass: settings.customGlassColor,
    ).apply();

    final String accentMode = settings.accentMode;
    final int? customAccentColor = settings.customAccentColor;

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
        final ColorScheme lightColorScheme =
            lightDynamic ??
            ColorScheme.fromSeed(
              seedColor: DnaApp._fallbackSeed,
              brightness: Brightness.light,
            );
        final ColorScheme darkColorScheme =
            darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: DnaApp._fallbackSeed,
              brightness: Brightness.dark,
            );
        return _buildMaterialApp(lightColorScheme, darkColorScheme);
      },
    );
  }

  Widget _buildMaterialApp(
    ColorScheme lightColorScheme,
    ColorScheme darkColorScheme,
  ) {
    return MaterialApp(
      title: 'DNA ULTRA 1.0',
      debugShowCheckedModeBanner: false,
      themeMode: _resolveThemeMode(widget.controller.settings.themeMode),
      theme: _buildTheme(lightColorScheme, _fontFamily),
      darkTheme: _buildTheme(darkColorScheme, _fontFamily),
      // 全局字号档位：0 = 跟随系统（原样放行），1..5 = 绝对倍率。
      //
      // 挂在 MaterialApp.builder（位于 Navigator 之上）⇒ 所有路由一起变，
      // **包括社区那一整块岛**（它内嵌在主应用里、共享同一个 MaterialApp）。
      // 社区这次不做豁免：只豁免"不该动的布局"，字本身跟着放大。
      //
      // 换档时由 AnimatedFontScale 把倍率插值过去（字是"长"过去的，
      // 不是"跳"过去的）；静止时不产生任何额外覆盖。
      // 全局画布：所有页面共享一层深色渐变底，玻璃卡片才有"浮起来"的层次。
      builder: (BuildContext context, Widget? child) => AppBackdrop(
        child: AnimatedFontScale(
          step: widget.controller.settings.fontSizeStep,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: AppRoot(controller: widget.controller),
    );
  }

  /// 当前字体族：`null` = 跟随系统字体（默认），否则内置思源黑体。
  String? get _fontFamily =>
      AppFont.familyFor(widget.controller.settings.fontFamilyMode);

  /// 由配色方案构建完整主题。
  ///
  /// 所有视觉规范集中在此处定义(参见 `DESIGN_SPEC.md`),业务代码不再手写
  /// 卡片圆角/描边/间距,避免同类元素在不同页面长得不一样。
  ///
  /// 字体:[fontFamily] 为 `null` 时**跟随系统字体** —— 手机主题引擎改写的
  /// 那套,用户自己挑的字体不会被应用覆盖(默认);传 `AppFont.family` 则用
  /// 内置**思源黑体**(Source Han Sans / Noto Sans SC,Regular 400 + Medium
  /// 500),后者根治「中英混排跳字体」「假粗」「跨平台不一致」三个问题,
  /// 代价是不跟随系统主题字体。两者在「设置 → 界面与显示 → 字体」里切换。
  static ThemeData _buildTheme(ColorScheme cs, String? fontFamily) {
    // 「深色玻璃」：深色模式把 Material 表面族整体压深，让半透明玻璃卡片
    // 浮在近黑画布上；浅色模式用冷调灰白画布兜底。
    final bool isDark = cs.brightness == Brightness.dark;
    final ColorScheme surface = isDark
        ? cs.copyWith(
            surface: AppSurfaces.canvasDark,
            onSurface: AppSurfaces.inkPrimary,
            onSurfaceVariant: AppSurfaces.inkSecondary,
            surfaceContainerLowest: AppSurfaces.surfaceContainerLowest,
            surfaceContainerLow: AppSurfaces.surfaceContainerLow,
            surfaceContainer: AppSurfaces.surfaceContainer,
            surfaceContainerHigh: AppSurfaces.surfaceContainerHigh,
            surfaceContainerHighest: AppSurfaces.surfaceContainerHighest,
            outlineVariant: AppSurfaces.outlineVariant,
          )
        : cs.copyWith(surface: AppSurfaces.canvasLight);
    final ThemeData base = ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    return ThemeData(
      colorScheme: surface,
      useMaterial3: true,
      fontFamily: fontFamily,
      // 内置思源黑体做了子集化（常用 CJK + 拉丁 + 假名 + 符号），
      // 遇到子集外的生僻字时回落系统字体，避免缺字。
      fontFamilyFallback: const <String>[
        'Microsoft YaHei UI',
        'PingFang SC',
        'sans-serif',
      ],
      scaffoldBackgroundColor:
          isDark ? AppSurfaces.canvasDark : AppSurfaces.canvasLight,

      // 桌面端:控件按鼠标操作收紧一档(触屏保持标准密度)。
      // 桌面上指针比手指精确得多,标准密度的行高与内边距偏松,
      // 一屏能看的内容太少。
      visualDensity: PlatformCapabilities.isDesktop
          ? VisualDensity.compact
          : VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // 卡片:扁平 + 细描边(全局统一,替代各页面 235 处手写样式)。
      // 卡片：玻璃层——半透明白色填充 + 1px 高光描边。
      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        color: isDark ? AppSurfaces.glassFill : AppSurfaces.glassFillLight,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(
            color:
                isDark ? AppSurfaces.glassBorder : AppSurfaces.glassBorderLight,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // 应用栏:无阴影、左对齐标题。
      appBarTheme: AppBarTheme(
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: surface.onSurface,
      ),

      // 列表项:保持 Material 默认密度(此前 minVerticalPadding 被设为 8、
      // contentPadding 垂直设为 8,导致侧边栏等列表项间距翻倍、过于松散)。
      listTileTheme: const ListTileThemeData(contentPadding: AppInsets.tile),

      // 输入框:统一圆角与内边距,使用描边风格而非填充。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? AppSurfaces.glassFillWeak : AppSurfaces.glassFillLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(
            color:
                isDark ? AppSurfaces.glassBorder : AppSurfaces.glassBorderLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(
            color:
                isDark ? AppSurfaces.glassBorder : AppSurfaces.glassBorderLight,
          ),
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
        color: isDark
            ? AppSurfaces.glassBorderSoft
            : AppSurfaces.glassBorderLight,
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
        backgroundColor:
            isDark ? AppSurfaces.glassFillStrong : AppSurfaces.glassFillLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(
            color:
                isDark ? AppSurfaces.glassBorder : AppSurfaces.glassBorderLight,
          ),
        ),
      ),

      // 底部抽屉:统一顶部圆角。
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? AppSurfaces.glassFillStrong : AppSurfaces.glassFillLight,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.topRounded),
      ),

      // 弹窗菜单:统一圆角。
      popupMenuTheme: PopupMenuThemeData(
        color:
            isDark ? AppSurfaces.glassFillStrong : AppSurfaces.glassFillLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smAll,
          side: BorderSide(
            color:
                isDark ? AppSurfaces.glassBorder : AppSurfaces.glassBorderLight,
          ),
        ),
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

  /// 本次冷启动是否已经尝试过「自动继续上次聊天」。
  ///
  /// 只尝试**一次**：从聊天页返回、切后台再回前台都不重试 ——
  /// 否则"回来一下又被弹走"会变成日常。
  bool _autoResumeTried = false;

  /// 自动续玩"成功确认"的定时器（见 ResumeService.confirmAttempt）。
  Timer? _resumeConfirmTimer;

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
    _requireAuth =
        PlatformCapabilities.biometricAuthSupported &&
        widget.controller.settings.requireAuthForApp;
    _showSplash = widget.controller.settings.showSplashAnimation;
    widget.controller.addListener(_onControllerChanged);
    // 启动后检查一次更新（可在「高级 → setupdatepage」关闭）。
    // 放在首帧之后发起，不阻塞启动。
    StartupUpdateCheck.schedule(context, widget.controller);
    // 社区（岛）的隐藏预热：首屏之后在后台把岛的初始化与「推荐」首屏数据
    // 做掉，用户点「社区」时不再转圈。关闭社区时不预热。
    _scheduleCommunityPreload();
    // 自动续玩：关掉开场动画时首帧就能尝试；开着的话等 _onSplashComplete。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoResume();
    });
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
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: FitText(
                      '欢迎使用网页版（预览版）',
                      style: TextStyle(
                        fontSize: AppFontSize.subtitle,
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _WebNoticeItem(
                icon: Icons.cloud_upload_outlined,
                title: '请手动备份数据',
                detail:
                    '网页版数据保存在浏览器中，清理浏览器数据会导致数据丢失。建议在「设置 → 数据管理 → 导出全部数据」中定期手动备份。',
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
    _resumeConfirmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      'Lifecycle: $state, requireAuth: $_requireAuth, authPassed: $_authPassed, hasBeenPaused: $_hasBeenPaused',
    );

    if (state == AppLifecycleState.paused) {
      // 记录进入后台的时间
      _pausedTime = DateTime.now();
      _hasBeenPaused = true;
      debugPrint('Lifecycle: App paused at $_pausedTime');
    } else if (state == AppLifecycleState.resumed) {
      // 只有真正从后台切回前台（之前执行过paused）才需要验证
      if (_hasBeenPaused && _requireAuth && _authPassed) {
        debugPrint(
          'Lifecycle: Resumed from background, checking if auth reset needed',
        );
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
    final bool newRequireAuth =
        PlatformCapabilities.biometricAuthSupported &&
        widget.controller.settings.requireAuthForApp;
    if ((newShowHome != _showHome || newRequireAuth != _requireAuth) &&
        mounted) {
      setState(() {
        _showHome = newShowHome;
        _requireAuth = newRequireAuth;
      });
    }
    // 用户在设置里重新打开社区：补一次预热（已预热过则内部直接返回）。
    _scheduleCommunityPreload();
  }

  /// 安排社区的隐藏预热。
  ///
  /// 两道闸门：**已过开屏**（用户已经/即将看到主界面）且**社区是开着的**。
  /// 未完成 OOBE 的新用户不做预热 —— 那会儿他还在填表，预热纯属浪费流量。
  void _scheduleCommunityPreload() {
    if (_showSplash || !_showHome) return;
    CommunityPreload.instance.schedule(
      enabled: () => widget.controller.settings.enableCommunity,
    );
  }

  void _onSplashComplete() {
    if (mounted) {
      setState(() => _showSplash = false);
    }
    _scheduleCommunityPreload();
    // 开屏结束到主界面是 500ms 的淡出（见 build 里的 AnimatedSwitcher）。
    // 等它落定再推聊天页，否则"主界面淡入"和"聊天页滑入"两段动画叠一起。
    Timer(const Duration(milliseconds: 520), () {
      if (mounted) _maybeAutoResume();
    });
  }

  void _onAuthPassed() {
    if (mounted) {
      setState(() => _authPassed = true);
    }
    // 应用锁通过可能就是自动续玩的最后一道闸门。
    _maybeAutoResume();
  }

  /// 「自动继续上次聊天」的闸门。
  ///
  /// 判断本身在 [shouldAutoResume] 里（纯函数，可单测）；这里只负责
  /// "条件不够就先等着" —— 开屏结束、解锁通过都会把这里再叫一次。
  /// 注意：条件不满足时**不置位** `_autoResumeTried`，所以不会被提前消费。
  void _maybeAutoResume() {
    if (!mounted) return;
    final AppController controller = widget.controller;
    if (!shouldAutoResume(
      enabled: controller.settings.autoOpenLastChat,
      splashDone: !_showSplash,
      oobeCompleted: _showHome,
      authRequired: _requireAuth,
      authPassed: _authPassed,
      alreadyAttempted: _autoResumeTried,
    )) {
      return;
    }
    _autoResumeTried = true;
    unawaited(_autoResume());
  }

  /// 真正把用户送回上次那场会话。
  ///
  /// 三步都不能省：先消化"上一次没走完的尝试"，再解析目标（失效静默放弃），
  /// 最后推之前立旗子、成功后清旗子 —— 这是防止"崩溃会话把用户焊死在里面"
  /// 的唯一保险（见 ResumeService）。
  Future<void> _autoResume() async {
    final ResumeService resume = ResumeService.instance;

    // ① 上次自动续玩没走到 confirm 就整进程没了 ⇒ 记一次失败。
    final int failures = await resume.consumeStaleAttempt();
    if (failures >= ResumeService.maxStartupFailures) {
      await widget.controller.saveAutoOpenLastChat(false);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showSnack(context, '上次的聊天打不开，已暂停自动继续');
          }
        });
      }
      return;
    }

    // ② 指针 → 可打开的目标；会话或角色任一没了就静默放弃（不弹窗）。
    final String? saved = await resume.lastConversationId();
    final ResumeTarget? target = resolveResumeTarget(
      conversationId: saved,
      conversations: widget.controller.conversations,
      tas: widget.controller.tas,
    );
    if (!mounted) return;
    if (target == null) {
      if (saved != null) {
        await resume.clearLast();
      }
      return;
    }

    // ③ 推入用的路由与手动点进聊天完全一致（MaterialPageRoute），
    //    否则"自动进入"会长得像另一个功能。
    await resume.beginAttempt(target.conversationId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatPage(
          controller: widget.controller,
          conversationId: target.conversationId,
          isGroup: target.isGroup,
        ),
      ),
    );
    _resumeConfirmTimer?.cancel();
    _resumeConfirmTimer = Timer(ResumeService.confirmDelay, () {
      unawaited(resume.confirmAttempt());
    });
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
        return FadeTransition(opacity: animation, child: child);
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
                AppSectionShell(controller: widget.controller),
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
              FitText(
                title,
                style: const TextStyle(fontWeight: AppWeight.medium),
              ),
              const SizedBox(height: 2),
              FitText(
                detail,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 崩溃落盘：桌面端没有崩溃上报，用户截图 + 日志是唯一可诊断路径。
/// 写到 `%TEMP%\dna_crash.log`，超过 512KB 轮转成 .1（只保留一份旧的）。
void _installCrashLog() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previous?.call(details);
    _appendCrashLog(
      'FlutterError: ${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _appendCrashLog('Uncaught: $error\n$stack');
    return false;
  };
}

void _appendCrashLog(String text) {
  if (kIsWeb) return;
  try {
    final String temp = Directory.systemTemp.path;
    final File file = File('$temp\\dna_crash.log');
    if (file.existsSync() && file.lengthSync() > 512 * 1024) {
      file.renameSync('$temp\\dna_crash.log.1');
    }
    file.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $text\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}