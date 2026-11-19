import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_section.dart';
import '../../widgets/fit_text.dart';
import '../settings_page.dart';

/// V2 主页（占位版本）。
///
/// 刻意只放两样东西：一行居中的 Hello World，和一个进入设置页的按钮。
/// **不带底栏、不带侧栏、不带任何栏目壳** —— 这一版先验证"换一套主页"
/// 这件事能跑通，界面内容等下一步再长。
///
/// 入口在设置 → 外观与聊天界面 → 启动与导航 → 「新版主页」（默认开启）。
class HomeV2Page extends StatelessWidget {
  const HomeV2Page({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FitText('Hello World', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _SettingsRoute(controller: controller),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
              label: const FitText('设置'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把一个设置页 push 出来（V2 主页没有栏目壳，所以自己装一层 Scaffold）。
class _SettingsRoute extends StatefulWidget {
  const _SettingsRoute({required this.controller});

  final AppController controller;

  @override
  State<_SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<_SettingsRoute> {
  /// 只装配一次：`settingsSection` 内部持有滚动位置（ValueNotifier），
  /// 每次 build 重新调用会把"从子页返回后回到原位置"这件事弄丢。
  late final SectionPageData _data = settingsSection(widget.controller);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _data.appBar(context),
      ),
      body: _data.body(context),
    );
  }
}
