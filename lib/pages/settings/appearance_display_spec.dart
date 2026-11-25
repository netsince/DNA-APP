/// 设置 → 界面与显示（配置驱动版）。
///
/// 取代 `appearance_display_page.dart` 的 604 行手写页面：现在只剩一份声明。
///
/// 三处无法用标量字段表达，用 [SettingAction] 兜住：
/// * 自定义强调色（弹 ColorPicker 后写 customAccentColor）；
/// * 应用图标（跳到 AppIconPage 并用缩略图展示当前图标）；
/// * 「滚动时自动全半屏」（只在开启半屏聊天时出现，用 visibleWhen 表达依赖）。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../splash/splash_animations.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:dna/theme/font_scale.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../models/app_settings.dart';
import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import 'app_icon_page.dart';
import 'spec/settings_spec.dart';

/// 自定义强调色：色块 + 点击弹取色器。
class _AccentColorTile extends StatelessWidget {
  const _AccentColorTile({required this.controller});

  final AppController controller;

  Future<void> _pickColor(BuildContext context) async {
    final int? currentArgb = controller.settings.customAccentColor;
    Color pickerColor = currentArgb != null
        ? Color(currentArgb)
        : AppColors.seed;
    final Color? result = await showDialog<Color>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const FitText('挑选专属主题色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color c) => pickerColor = c,
            enableAlpha: false,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(pickerColor),
            child: const FitText('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await controller.patchSettings('customAccentColor', result.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int? argb = controller.settings.customAccentColor;
    final Color swatch = argb != null ? Color(argb) : AppColors.seed;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.a40)),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
      title: const FitText('点击挑选颜色'),
      onTap: () => _pickColor(context),
    );
  }
}

/// 应用图标入口：缩略图 + 当前名称，点击进图标页。
class _AppIconTile extends StatelessWidget {
  const _AppIconTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppIconOption option = AppIconService.optionForKey(
      controller.settings.appIcon,
    );
    final bool supported = AppIconService.isSupported || kIsWeb;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.asset(
          option.assetPath,
          width: 44,
          height: 44,
          errorBuilder: (_, _, _) => Container(
            width: 44,
            height: 44,
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(Icons.android, size: 24, color: cs.outline),
          ),
        ),
      ),
      title: FitText(option.label),
      subtitle: FitText(
        supported
            ? (kIsWeb ? '点击更换浏览器标签页图标' : '点击更换桌面启动图标')
            : '当前平台不支持切换',
        style: AppTextStyles.caption(Theme.of(context)).copyWith(
          color: cs.outline,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppIconPage(controller: controller),
        ),
      ),
    );
  }
}

/// 「界面与显示」页的完整声明。
final FieldsEntry appearanceEntry = FieldsEntry(
  id: 'appearance',
  groupId: SettingsGroupId.appearance,
  icon: Icons.dashboard_customize_outlined,
  title: '外观与聊天界面',
  subtitle: '明暗主题、强调色、气泡与半屏模式',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'appearance.theme',
      icon: Icons.palette_outlined,
      title: '明暗与配色',
      items: <SettingItemSpec>[
        SettingChoice<String>(
          id: 'appearance.themeMode',
          title: '明暗外观',
          key: 'themeMode',
          defaultValue: 'system',
          options: <ChoiceOption<String>>[
            ChoiceOption<String>(
              value: 'system',
              label: '跟随系统',
              icon: Icons.brightness_auto,
            ),
            ChoiceOption<String>(
              value: 'light',
              label: '亮色',
              icon: Icons.light_mode,
            ),
            ChoiceOption<String>(
              value: 'dark',
              label: '暗色',
              icon: Icons.dark_mode,
            ),
          ],
        ),
        SettingChoice<String>(
          id: 'appearance.accentMode',
          title: '强调色',
          key: 'accentMode',
          defaultValue: 'auto',
          options: <ChoiceOption<String>>[
            ChoiceOption<String>(value: 'auto', label: '自动取色'),
            ChoiceOption<String>(value: 'custom', label: '自定义'),
          ],
        ),
        SettingAction(
          id: 'appearance.customAccentColor',
          title: '自定义强调色',
          searchable: true,
          visibleWhen: (SettingsRuntime r) => r.settings.accentMode == 'custom',
          builder: (BuildContext context, AppController c) =>
              _AccentColorTile(controller: c),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'appearance.font',
      icon: Icons.text_fields,
      title: '字体',
      items: <SettingItemSpec>[
        SettingChoice<String>(
          id: 'appearance.fontFamilyMode',
          title: '字体来源',
          // 旧页面里这两项紧跟在分组标题下，没有再画一遍字段标题。
          showTitle: false,
          key: 'fontFamilyMode',
          defaultValue: 'system',
          options: <ChoiceOption<String>>[
            ChoiceOption<String>(
              value: 'system',
              label: '系统字体',
            ),
            ChoiceOption<String>(
              value: 'sourcehan',
              label: '思源黑体',
            ),
          ],
        ),
        SettingInt(
          id: 'appearance.fontSizeStep',
          title: '字号',
          key: 'fontSizeStep',
          defaultValue: 0,
          min: 0,
          max: AppFontScale.maxStep,
          step: 1,
          editor: NumberEditor.slider,
          saveMode: SettingsSaveMode.onRelease,
          labelOf: (int value) => AppFontScale.labelOf(value),
        ),
        SettingInt(
          id: 'appearance.snackDuration',
          title: '提示条停留时长',
          hint: '底部提示（例如「已复制」）自动消失的时间。',
          key: 'snackDurationMs',
          defaultValue: kDefaultSnackDurationMs,
          min: 1000,
          max: 10000,
          step: 500,
          unit: '毫秒',
          editor: NumberEditor.slider,
          saveMode: SettingsSaveMode.onRelease,
          // 有副作用：改完要立刻应用到 SnackBar 主题，所以走 writeOverride。
          writeOverride: (AppController c, int value) =>
              c.applySnackDuration(value),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'appearance.elements',
      icon: Icons.tune,
      title: '界面元素',
      items: <SettingItemSpec>[
        SettingChoice<String>(
          id: 'appearance.chatInputStyle',
          title: '聊天输入栏样式',
          key: 'chatInputStyle',
          defaultValue: 'capsule',
          options: <ChoiceOption<String>>[
            ChoiceOption<String>(value: 'capsule', label: '胶囊'),
            ChoiceOption<String>(value: 'classic', label: '经典'),
          ],
        ),
        SettingToggle(
          id: 'appearance.showUploadButton',
          title: '显示上传文件按钮',
          key: 'showUploadButton',
          defaultValue: true,
        ),
        SettingInt(
          id: 'appearance.chatMaskStrength',
          title: '背景遮罩强度',
          subtitle: '数值越大背景越暗、文字越清晰。',
          key: 'chatMaskStrength',
          defaultValue: 75,
          min: 0,
          max: 100,
          step: 1,
          editor: NumberEditor.slider,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingInt(
          id: 'appearance.chatBubbleOpacity',
          title: '气泡透明度',
          subtitle: '数值越小，背景透出越多。',
          key: 'chatBubbleOpacity',
          defaultValue: 100,
          min: 0,
          max: 100,
          step: 1,
          editor: NumberEditor.slider,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingToggle(
          id: 'appearance.halfScreenChat',
          title: '半屏聊天',
          subtitle: '只占下半屏，上面留给立绘。',
          key: 'halfScreenChat',
        ),
        SettingToggle(
          // key 保留旧名（持久化兼容）；语义已从「滚动自动切换」改成
          // 「顶栏是否显示展开按钮」—— 自动切换的布局变化按审计删掉了，
          // 留一个没有效果的开关比没有开关更糟。
          id: 'appearance.dynamicHalfScreen',
          title: '顶栏显示展开按钮',
          key: 'dynamicHalfScreen',
          visibleWhen: (SettingsRuntime r) => r.settings.halfScreenChat,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'appearance.quickButtons',
      icon: Icons.touch_app_outlined,
      title: '气泡快捷按钮',
      description: '关掉后仍可长按消息使用。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'appearance.showMessageAvatar',
          title: '角色头像',
          subtitle: '显示在气泡左上角。',
          key: 'showMessageAvatar',
        ),
        SettingToggle(
          id: 'appearance.showMessageRetry',
          title: '重新生成',
          key: 'showMessageRetry',
        ),
        SettingToggle(
          id: 'appearance.showMessageCopy',
          title: '复制',
          key: 'showMessageCopy',
        ),
        SettingToggle(
          id: 'appearance.showMessageContinue',
          title: '继续说',
          key: 'showMessageContinue',
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'appearance.startup',
      icon: Icons.rocket_launch_outlined,
      title: '启动与导航',
      items: <SettingItemSpec>[
        // 开场动画：选项**由 kSplashAnimations 生成**，新增一段动画不用改这里。
        SettingChoice<String>(
          id: 'appearance.splashAnimation',
          title: '开场动画',
          key: 'splashAnimation',
          defaultValue: kDefaultSplashAnimationId,
          layout: ChoiceLayout.radioList,
          options: <ChoiceOption<String>>[
            for (final SplashAnimationSpec spec in kSplashAnimations)
              ChoiceOption<String>(
                value: spec.id,
                label: spec.label,
                subtitle: spec.description,
              ),
          ],
        ),
        SettingToggle(
          id: 'appearance.autoOpenLastChat',
          title: '自动继续上次聊天',
          key: 'autoOpenLastChat',
        ),
        SettingToggle(
          id: 'appearance.showBottomNav',
          title: '底部导航栏',
          subtitle: '常驻四个主页面。',
          key: 'showBottomNav',
        ),
        SettingToggle(
          id: 'appearance.enableCommunity',
          title: '社区',
          subtitle: '关闭后底栏不再显示社区。',
          key: 'enableCommunity',
        ),
        SettingToggle(
          id: 'appearance.showExitToMainApp',
          title: '返回主应用按钮',
          subtitle: '关闭后靠横向滑动或系统返回退出',
          key: 'showExitToMainApp',
        ),
        SettingToggle(
          id: 'appearance.chatQuickSidebar',
          title: '聊天快速切换栏',
          subtitle: '横屏聊天时左侧显示角色与聊天快捷列表。',
          key: 'chatQuickSidebar',
        ),
        SettingToggle(
          id: 'appearance.chatSwipeSwitch',
          title: '左右滑动切换',
          key: 'chatSwipeSwitch',
        ),
        SettingToggle(
          id: 'appearance.showTokenDashboard',
          title: '记忆容量仪表盘',
          subtitle: '输入栏上方显示上下文占用。',
          key: 'showTokenDashboard',
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'appearance.icon',
      icon: Icons.apps_outlined,
      title: '应用图标',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'appearance.appIcon',
          title: '应用图标',
          builder: (BuildContext context, AppController c) =>
              _AppIconTile(controller: c),
        ),
      ],
    ),
  ],
);
