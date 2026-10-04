import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import '../../state/app_controller.dart';

/// 「自由剪图」设置页。
///
/// 通过「高级 → 命令」输入 `freeimage` 进入。
///
/// 打开后，**所有图片编辑器**的裁剪比例限制一律失效：角色卡形象（1:1 / 16:9 / 9:16）、
/// TA 形象、社区头像，裁剪界面都不再锁定比例，想剪成什么比例就剪什么比例。
///
/// 实现上只改一处规则：裁剪入口旁的 `FreeImageCrop`（见
/// lib/island_app/widgets/card_crop_page.dart），值直接读本控制器的当前设置。
class FreeImageSettingsPage extends StatelessWidget {
  const FreeImageSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('自由剪图')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? _) {
          final bool enabled = controller.settings.freeImageCrop;
          return ListView(
            padding: AppInsets.page,
            children: <Widget>[
              SettingSection(
                icon: Icons.crop_free,
                title: '裁剪比例',
                description: '关闭时按各槽位的固定比例锁定。',
                children: <Widget>[
                  SettingSwitch(
                    title: '自由剪图',
                    subtitle: enabled
                        ? '所有图片编辑器都不再限制比例'
                        : '角色卡 1:1 / 16:9 / 9:16、TA 形象、社区头像按比例锁定',
                    value: enabled,
                    onChanged: (bool v) => controller.saveFreeImageCrop(v),
                  ),
                ],
              ),
              AppSpacing.hLg,
              SettingSection(
                icon: Icons.info_outline,
                title: '说明',
                children: <Widget>[
                  const SettingHint(
                    '角色卡的形象槽位仍受服务端比例校验：剪成别的比例后，'
                    '发布/保存时会被拒绝并提示所需比例。TA 形象与社区头像不受影响。',
                    icon: Icons.warning_amber_rounded,
                  ),
                  AppSpacing.hSm,
                  const SettingHint(
                    '开启后裁剪界面不再锁定比例，也不再出现比例菜单，'
                    '可以自由拖拽裁剪框。',
                    icon: Icons.crop_free,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
