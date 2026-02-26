import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final settings = controller.settings;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Duet Nurturing Ally'),
            actions: <Widget>[
              IconButton(
                tooltip: '设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => SettingsPage(controller: controller),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          drawer: AppDrawer(controller: controller, current: AppSection.home),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('欢迎使用 与汝共奏', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text('当前 Base URL: ${settings.baseUrl.isEmpty ? '(未设置)' : settings.baseUrl}'),
                        const SizedBox(height: 6),
                        Text('当前模型: ${settings.selectedModel.isEmpty ? '(未选择)' : settings.selectedModel}'),
                        const SizedBox(height: 16),
                        const Text('设置可在右上角随时修改，修改后立即生效。'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
