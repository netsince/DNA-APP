import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'sampler_settings_spec.dart';
import 'spec/settings_fields_page.dart';

/// 兼容壳：页面本体已改成声明驱动，见 sampler_settings_spec.dart。
///
/// 保留类名是因为 AI 服务页与模型编辑页都直接 push 它。
class SamplerSettingsPage extends StatelessWidget {
  const SamplerSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) =>
      SettingsFieldsPage(entry: samplerEntry, controller: controller);
}
