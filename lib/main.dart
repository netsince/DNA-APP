import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/oobe_page.dart';
import 'services/openai_service.dart';
import 'services/role_service.dart';
import 'services/settings_service.dart';
import 'services/world_service.dart';
import 'services/conversation_service.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = AppController(
    settingsService: SettingsService(),
    openAiService: OpenAiService(),
    roleService: RoleService(),
    worldService: WorldService(),
    conversationService: ConversationService(),
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

  runZonedGuarded(
    () => runApp(DnaApp(controller: controller)),
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
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: AppRoot(controller: controller),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final Widget child = controller.settings.completedOobe
            ? HomePage(controller: controller)
            : OobePage(controller: controller);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<bool>(controller.settings.completedOobe),
            child: child,
          ),
        );
      },
    );
  }
}
