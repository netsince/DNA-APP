import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/app_settings.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/server_setup_page.dart';
import 'package:dna/island_app/shared_prefs.dart';
import 'package:dna/island_app/shutdown_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动前预热 SharedPreferences 缓存：本地存储的异步加载不阻塞 UI，且
  // 后续所有 getInstance() 都能直接复用缓存，避免启动时额外的 IO 等待。
  await SharedPrefs.init();
  // 预热服务器地址：让首帧即可同步判断「是否已配置」，已配置的安装不会闪一下启动态。
  await ServerConfig.getBaseUrl();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettings _settings = AppSettings.instance;

  /// 启动态：仅在「尚未配置服务器地址」的首次启动期间为 true（正在校验官方默认地址）。
  bool _booting = !ServerConfig.hasBaseUrl;
  bool _needsSetup = false;
  String? _setupError;
  bool _shutdownDismissed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 启动初始化：读取本地设置与服务器地址；首次启动（尚无地址）时先尝试官方默认地址。
  ///
  /// 官方用户因此无需任何输入即可进入主界面；自建用户若首次校验失败会落到兜底设置页，
  /// 在那里检查网络或改填自己的地址。已配置过的安装不做任何校验，直接进主界面——
  /// 避免把一次临时网络抖动变成强制设置页。
  Future<void> _init() async {
    await Future.wait([_settings.load(), ServerConfig.getBaseUrl()]);
    if (!ServerConfig.hasBaseUrl) {
      final err = await ApiClient.instance.validateServer(
        ServerConfig.defaultBaseUrl,
      );
      if (err == null) {
        await ServerConfig.setBaseUrl(ServerConfig.defaultBaseUrl);
      } else {
        _needsSetup = true;
        _setupError = err;
      }
    }
    _booting = false;
    if (mounted) setState(() {});
    // 还没配好服务器时先不拉站点配置/会话，等用户设置完再拉（见 _onSetupDone）。
    if (_needsSetup) return;
    await _loadSiteConfig();
    // 后台恢复登录会话（token 校验），不阻塞界面。
    await AuthSession.instance.load();
    // 应用启动即预取表情包目录（公开接口），避免首次打开表情包面板时再等待。
    // 不阻塞启动，失败时静默回退（渲染时按纯文本显示）。
    StickerCatalog.instance.ensureLoaded();
  }

  /// 后台拉取站点配置；失败回退默认值，不阻塞、不阻断界面。
  Future<void> _loadSiteConfig() async {
    await SiteConfig.instance.load();
    if (mounted) setState(() {});
  }

  void _onSetupDone() {
    setState(() {
      _needsSetup = false;
      _setupError = null;
    });
    _loadSiteConfig();
    AuthSession.instance.load();
    StickerCatalog.instance.ensureLoaded();
  }

  Color _seed() {
    final custom = _settings.accentColor;
    return custom == null ? Colors.deepPurple : Color(custom);
  }

  /// 集中定义全局组件默认样式，减少各页面局部 override 造成的不一致。
  ThemeData _buildTheme(Color seed, Brightness brightness) {
    // 预测性返回（Predictive Back）：Android 13+ 的返回手势预览动画。
    const pageTransitionsTheme = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    );
    // 先算出配色，卡片描边要用它的 outlineVariant（与主程序同一套取色逻辑）。
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 字号体系与主程序共用同一份重映射：Material 默认的 titleLarge 是 22、
      // headlineSmall 是 24，不重映射的话同一行代码在两边字号完全不同。
      textTheme: AppTextStyles.buildTextTheme(
        ThemeData(colorScheme: scheme).textTheme,
      ),
      pageTransitionsTheme: pageTransitionsTheme,
      // 顶栏：无阴影。标题对齐不再显式居中 ——统一跟主程序左对齐。
      appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 0.5),
      // 卡片：扁平 + 细描边，与主程序 `main.dart` 的 cardTheme 同一套规范。
      // 主程序的层级靠描边区分而不是阴影（见 AppBorder.cardShape）；
      // 社区独立运行时若不跟上，同一张卡片在「App 内」和「独立运行」会长得不一样。
      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        shape: AppBorder.cardShape(scheme),
        clipBehavior: Clip.antiAlias,
      ),
      // 分割线：缩进与列表项图标对齐（主程序同款 AppBorder.dividerIndent）。
      dividerTheme: const DividerThemeData(indent: AppBorder.dividerIndent),
      // 输入框默认描边样式（圆角 + 描边），页面无需再写 border: OutlineInputBorder()。
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      // 统一的浮动 SnackBar。
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 360,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final site = SiteConfig.instance;
        final seed = _seed();

        Widget home;
        if (_booting) {
          home = const _BootSplash();
        } else if (_needsSetup) {
          home = ServerSetupPage(
            onDone: _onSetupDone,
            initialError: _setupError,
          );
        } else if (site.shutdownEnabled && !_shutdownDismissed) {
          home = ShutdownPage(
            onDismissed: () => setState(() => _shutdownDismissed = true),
          );
        } else {
          home = const RootShell();
        }

        return MaterialApp(
          title: site.siteName,
          themeMode: _settings.themeMode,
          theme: _buildTheme(seed, Brightness.light),
          darkTheme: _buildTheme(seed, Brightness.dark),
          home: home,
        );
      },
    );
  }
}

/// 首次启动校验官方服务器期间的极简启动态（正常情况下只出现一次、时间很短）。
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接官方服务器…'),
          ],
        ),
      ),
    );
  }
}
