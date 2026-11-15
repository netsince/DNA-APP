import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'free_image_settings_spec.dart';
import 'spec/settings_fields_page.dart';

/// 兼容壳：页面本体已改成声明驱动，见 free_image_settings_spec.dart。
///
/// 保留这个类名和构造签名，是因为开发者选项的 `freeimage` 命令和 free_image_crop_test 还在用它。新代码请直接用
/// `SettingsFieldsPage(entry: freeImageCropEntry, controller: …)`。
class FreeImageSettingsPage extends StatelessWidget {
  const FreeImageSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) =>
      SettingsFieldsPage(entry: freeImageCropEntry, controller: controller);
}
