import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'appearance_display_spec.dart';
import 'spec/settings_fields_page.dart';

/// 兼容壳：页面本体已改成声明驱动，见 appearance_display_spec.dart。
///
/// 保留这个类名和构造签名，是因为有 4 个字号/启动测试直接 pump 它。新代码请直接用
/// `SettingsFieldsPage(entry: appearanceEntry, controller: …)`。
class AppearanceDisplayPage extends StatelessWidget {
  const AppearanceDisplayPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) =>
      SettingsFieldsPage(entry: appearanceEntry, controller: controller);
}
