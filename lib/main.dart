import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/oobe_page.dart';
import 'services/openai_service.dart';
import 'services/ta_service.dart';
import 'services/settings_service.dart';
import 'services/world_service.dart';
import 'services/conversation_service.dart';
import 'services/group_conversation_service.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final controller = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
        worldService: WorldService(),
        conversationService: ConversationService(),
        groupConversationService: GroupConversationService(),
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

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF147B74);
    return MaterialApp(
      title: 'Duet Nurturing Ally',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
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
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
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
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _showHome = widget.controller.settings.completedOobe;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final bool newShowHome = widget.controller.settings.completedOobe;
    if (newShowHome != _showHome && mounted) {
      setState(() => _showHome = newShowHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 IndexedStack 避免页面重建，移除动画以减少卡顿
    return IndexedStack(
      index: _showHome ? 1 : 0,
      children: <Widget>[
        OobePage(controller: widget.controller),
        HomePage(controller: widget.controller),
      ],
    );
  }
}
