import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'pages/oobe_page.dart';
import 'pages/splash_page.dart';
import 'services/openai_service.dart';
import 'services/ta_service.dart';
import 'services/settings_service.dart';
import 'state/app_controller.dart';

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

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
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

class DnaApp extends StatelessWidget {
  const DnaApp({super.key, required this.controller});

  final AppController controller;

  static const Color _fallbackSeed = Color(0xFF147B74);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme lightColorScheme = lightDynamic ?? ColorScheme.fromSeed(
          seedColor: _fallbackSeed,
          brightness: Brightness.light,
        );
        final ColorScheme darkColorScheme = darkDynamic ?? ColorScheme.fromSeed(
          seedColor: _fallbackSeed,
          brightness: Brightness.dark,
        );

        return MaterialApp(
          title: 'Duet Nurturing Ally',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
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
          home: AppRoot(controller: controller),
        );
      },
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showHome = widget.controller.settings.completedOobe;
    _requireAuth = widget.controller.settings.requireAuthForApp;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('Lifecycle: $state, requireAuth: $_requireAuth, authPassed: $_authPassed, hasBeenPaused: $_hasBeenPaused');
    
    if (state == AppLifecycleState.paused) {
      // 记录进入后台的时间
      _pausedTime = DateTime.now();
      _hasBeenPaused = true;
      print('Lifecycle: App paused at $_pausedTime');
    } else if (state == AppLifecycleState.resumed) {
      // 只有真正从后台切回前台（之前执行过paused）才需要验证
      if (_hasBeenPaused && _requireAuth && _authPassed) {
        print('Lifecycle: Resumed from background, checking if auth reset needed');
        _hasBeenPaused = false;
        
        // 只有在后台停留超过1秒才需要重新验证（避免快速切换）
        if (_pausedTime != null) {
          final Duration diff = DateTime.now().difference(_pausedTime!);
          print('Lifecycle: Time in background: ${diff.inSeconds}s');
          if (diff.inSeconds >= 1) {
            print('Lifecycle: Resetting auth state');
            setState(() => _authPassed = false);
          }
        }
      }
    }
  }

  void _onControllerChanged() {
    final bool newShowHome = widget.controller.settings.completedOobe;
    final bool newRequireAuth = widget.controller.settings.requireAuthForApp;
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
