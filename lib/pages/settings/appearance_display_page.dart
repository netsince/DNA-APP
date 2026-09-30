// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:dna/theme/tokens.dart';

import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'app_icon_page.dart';

/// 设置 → 界面与显示。
///
/// 由原「主题与颜色」「应用与启动」「聊天界面」三页**合并**而来。
/// 三者本质都是「界面长什么样」,拆成三个入口只会让用户在设置主页多跳两次;
/// 合并后用 [SettingSection] 在页内分区,一次看全。
class AppearanceDisplayPage extends StatefulWidget {
  const AppearanceDisplayPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearanceDisplayPage> createState() => _AppearanceDisplayPageState();
}

class _AppearanceDisplayPageState extends State<AppearanceDisplayPage> {
  static const Color _defaultAccent = AppColors.seed;

  // ---- 主题 ----
  late String _themeMode;
  late String _accentMode;
  int? _customAccentColor;

  // ---- 应用与启动 ----
  bool _showSplash = true;
  bool _showBottomNav = false;
  bool _chatQuickSidebar = true;
  bool _chatSwipeSwitch = true;
  bool _showTokenDashboard = false;
  String _iconKey = 'default';
  final bool _iconSupported = AppIconService.isSupported || kIsWeb;

  // ---- 聊天界面 ----
  int _chatMaskStrength = 75;
  int _chatBubbleOpacity = 100;
  bool _halfScreenChat = false;
  bool _dynamicHalfScreen = false;
  bool _showMessageAvatar = true;
  bool _showMessageRetry = true;
  bool _showMessageCopy = true;
  bool _showMessageContinue = true;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _themeMode = s.themeMode;
    _accentMode = s.accentMode;
    _customAccentColor = s.customAccentColor;

    _showSplash = s.showSplashAnimation;
    _showBottomNav = s.showBottomNav;
    _chatQuickSidebar = s.chatQuickSidebar;
    _chatSwipeSwitch = s.chatSwipeSwitch;
    _showTokenDashboard = s.showTokenDashboard;
    _iconKey = s.appIcon;

    _chatMaskStrength = s.chatMaskStrength;
    _chatBubbleOpacity = s.chatBubbleOpacity;
    _halfScreenChat = s.halfScreenChat;
    _dynamicHalfScreen = s.dynamicHalfScreen;
    _showMessageAvatar = s.showMessageAvatar;
    _showMessageRetry = s.showMessageRetry;
    _showMessageCopy = s.showMessageCopy;
    _showMessageContinue = s.showMessageContinue;
  }

  AppIconOption get _currentIcon {
    for (final AppIconOption opt in AppIconService.availableOptions) {
      if (opt.key == _iconKey) return opt;
    }
    return AppIconOption.defaultIcon;
  }

  Color get _currentCustomColor =>
      _customAccentColor != null ? Color(_customAccentColor!) : _defaultAccent;

  Future<void> _saveQuickButtons() =>
      widget.controller.saveMessageQuickButtons(
        showAvatar: _showMessageAvatar,
        showRetry: _showMessageRetry,
        showCopy: _showMessageCopy,
        showContinue: _showMessageContinue,
      );

  Future<void> _selectTheme(String mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    await widget.controller.saveThemeMode(mode);
  }

  Future<void> _selectAccentMode(String mode) async {
    if (_accentMode == mode) return;
    setState(() => _accentMode = mode);
    await widget.controller.saveAccentMode(mode);
  }

  Future<void> _pickColor() async {
    Color pickerColor = _currentCustomColor;
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
    if (result != null && mounted) {
      setState(() => _customAccentColor = result.toARGB32());
      await widget.controller.saveCustomAccentColor(result.toARGB32());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('界面与显示')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 明暗与配色 =====
          SettingSection(
            title: '明暗与配色',
            icon: Icons.palette_outlined,
            children: <Widget>[
              FitText(
                '明暗外观',
                style: ts.bodyLarge?.copyWith(fontWeight: AppWeight.medium),
              ),
              AppSpacing.hXs,
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'system',
                    label: FitText('跟随系统'),
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment<String>(
                    value: 'light',
                    label: FitText('亮色'),
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment<String>(
                    value: 'dark',
                    label: FitText('暗色'),
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: <String>{_themeMode},
                onSelectionChanged: (Set<String> val) => _selectTheme(val.first),
              ),
              AppSpacing.hLg,
              FitText(
                '强调色',
                style: ts.bodyLarge?.copyWith(fontWeight: AppWeight.medium),
              ),
              AppSpacing.hXs,
              FitText(
                _accentMode == 'auto'
                    ? '自动取色：聊天页会提取角色立绘主色，沉浸感更强。'
                    : '自定义：全局统一使用你挑选的主题色。',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
              AppSpacing.hSm,
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'auto',
                    label: FitText('自动取色'),
                  ),
                  ButtonSegment<String>(
                    value: 'custom',
                    label: FitText('自定义'),
                  ),
                ],
                selected: <String>{_accentMode},
                onSelectionChanged: (Set<String> val) =>
                    _selectAccentMode(val.first),
              ),
              if (_accentMode == 'custom') ...<Widget>[
                AppSpacing.hSm,
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _currentCustomColor,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                  ),
                  title: const FitText('点击挑选颜色'),
                  trailing: const Icon(Icons.colorize),
                  onTap: _pickColor,
                ),
              ],
            ],
          ),

          // ===== 2. 界面元素 =====
          SettingSection(
            title: '界面元素',
            icon: Icons.tune,
            children: <Widget>[
              FitText(
                '背景遮罩强度',
                style: ts.bodyLarge?.copyWith(fontWeight: AppWeight.medium),
              ),
              AppSpacing.hXs,
              FitText(
                '数值越大背景越暗、文字越清晰。',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: _chatMaskStrength.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (v) =>
                          setState(() => _chatMaskStrength = v.round()),
                      onChangeEnd: (v) =>
                          widget.controller.saveChatMaskStrength(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: FitText('$_chatMaskStrength',
                        textAlign: TextAlign.right, style: ts.bodyMedium),
                  ),
                ],
              ),
              AppSpacing.hSm,
              FitText(
                '气泡透明度',
                style: ts.bodyLarge?.copyWith(fontWeight: AppWeight.medium),
              ),
              AppSpacing.hXs,
              FitText(
                '数值越小，背景透出越多。',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: _chatBubbleOpacity.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (v) =>
                          setState(() => _chatBubbleOpacity = v.round()),
                      onChangeEnd: (v) =>
                          widget.controller.saveChatBubbleOpacity(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: FitText('$_chatBubbleOpacity',
                        textAlign: TextAlign.right, style: ts.bodyMedium),
                  ),
                ],
              ),
              AppSpacing.hSm,
              SettingSwitch(
                title: '半屏聊天',
                subtitle: '聊天只占下半屏，上半屏留给你欣赏立绘。',
                value: _halfScreenChat,
                onChanged: (bool v) async {
                  setState(() => _halfScreenChat = v);
                  await widget.controller.saveHalfScreenChat(v);
                },
              ),
              if (_halfScreenChat)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.md),
                  child: SettingSwitch(
                    title: '滚动时自动全半屏',
                    subtitle: '翻历史时展开，滚回底部时收成半屏。',
                    value: _dynamicHalfScreen,
                    onChanged: (bool v) async {
                      setState(() => _dynamicHalfScreen = v);
                      await widget.controller.saveDynamicHalfScreen(v);
                    },
                  ),
                ),
            ],
          ),

          // ===== 3. 气泡快捷按钮 =====
          SettingSection(
            title: '气泡快捷按钮',
            icon: Icons.touch_app_outlined,
            description: '关掉后仍可长按消息使用。',
            children: <Widget>[
              SettingSwitch(
                title: '角色头像',
                subtitle: '在气泡左上角显示头像，群聊里更好认人。',
                value: _showMessageAvatar,
                onChanged: (bool v) {
                  setState(() => _showMessageAvatar = v);
                  _saveQuickButtons();
                },
              ),
              SettingSwitch(
                title: '重新生成',
                value: _showMessageRetry,
                onChanged: (bool v) {
                  setState(() => _showMessageRetry = v);
                  _saveQuickButtons();
                },
              ),
              SettingSwitch(
                title: '复制',
                value: _showMessageCopy,
                onChanged: (bool v) {
                  setState(() => _showMessageCopy = v);
                  _saveQuickButtons();
                },
              ),
              SettingSwitch(
                title: '继续说',
                subtitle: '让 AI 接着没写完的内容继续。',
                value: _showMessageContinue,
                onChanged: (bool v) {
                  setState(() => _showMessageContinue = v);
                  _saveQuickButtons();
                },
              ),
            ],
          ),

          // ===== 4. 启动与导航 =====
          SettingSection(
            title: '启动与导航',
            icon: Icons.rocket_launch_outlined,
            children: <Widget>[
              SettingSwitch(
                title: '开场动画',
                subtitle: '关闭后启动直接进主界面。',
                value: _showSplash,
                onChanged: (bool v) {
                  setState(() => _showSplash = v);
                  widget.controller
                      .saveSplashAnimation(showSplashAnimation: v);
                },
              ),
              SettingSwitch(
                title: '底部导航栏',
                subtitle: '底部常驻四个主页面，方便单手切换。',
                value: _showBottomNav,
                onChanged: (bool v) {
                  setState(() => _showBottomNav = v);
                  widget.controller.saveShowBottomNav(v);
                },
              ),
              SettingSwitch(
                title: '聊天快速切换栏',
                subtitle: '横屏聊天时左侧显示角色与聊天快捷列表。',
                value: _chatQuickSidebar,
                onChanged: (bool v) {
                  setState(() => _chatQuickSidebar = v);
                  widget.controller.saveChatQuickSidebar(v);
                },
              ),
              SettingSwitch(
                title: '左右滑动切换',
                subtitle: '聊天时左右滑动切换角色。',
                value: _chatSwipeSwitch,
                onChanged: (bool v) {
                  setState(() => _chatSwipeSwitch = v);
                  widget.controller.saveChatSwipeSwitch(v);
                },
              ),
              SettingSwitch(
                title: '记忆容量仪表盘',
                subtitle: '在输入栏上方显示当前上下文占用进度。',
                value: _showTokenDashboard,
                onChanged: (bool v) {
                  setState(() => _showTokenDashboard = v);
                  widget.controller.saveShowTokenDashboard(v);
                },
              ),
            ],
          ),

          // ===== 5. 应用图标 =====
          SettingSection(
            title: '应用图标',
            icon: Icons.apps_outlined,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.asset(
                    _currentIcon.assetPath,
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
                title: FitText(_currentIcon.label),
                subtitle: FitText(
                  _iconSupported
                      ? (kIsWeb ? '点击更换浏览器标签页图标' : '点击更换桌面启动图标')
                      : '当前平台不支持切换',
                  style: ts.bodySmall?.copyWith(color: cs.outline),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AppIconPage(controller: widget.controller),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
