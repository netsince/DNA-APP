// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 外观与体验 → 主题与颜色。
///
/// 应用主题模式与强调色（自动提取 / 自定义指定）。
class AppearanceThemePage extends StatefulWidget {
  const AppearanceThemePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearanceThemePage> createState() => _AppearanceThemePageState();
}

class _AppearanceThemePageState extends State<AppearanceThemePage> {
  static const Color _defaultAccent = Color(0xFF147B74);

  late String _themeMode;
  late String _accentMode;
  int? _customAccentColor;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _themeMode = s.themeMode;
    _accentMode = s.accentMode;
    _customAccentColor = s.customAccentColor;
  }

  Color get _currentCustomColor =>
      _customAccentColor != null ? Color(_customAccentColor!) : _defaultAccent;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('主题与颜色')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 主题明暗模式 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('明暗外观', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FitText('选择应用的全局明暗风格。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'system',
                        label: FitText('跟随系统'),
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment<String>(
                        value: 'light',
                        label: FitText('亮色模式'),
                        icon: Icon(Icons.light_mode),
                      ),
                      ButtonSegment<String>(
                        value: 'dark',
                        label: FitText('暗色模式'),
                        icon: Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: <String>{_themeMode},
                    onSelectionChanged: (Set<String> val) => _selectTheme(val.first),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 主题强调色 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('强调色方案', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FitText(
                    _accentMode == 'auto'
                        ? '自动取色：主界面跟随系统，聊天界面自动提取角色立绘主色，沉浸感更深。'
                        : '自定义取色：全局统一使用你挑选的专属主题色。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'auto',
                        label: FitText('自动取色 (推荐)'),
                      ),
                      ButtonSegment<String>(
                        value: 'custom',
                        label: FitText('自定义单色'),
                      ),
                    ],
                    selected: <String>{_accentMode},
                    onSelectionChanged: (Set<String> val) => _selectAccentMode(val.first),
                  ),
                  if (_accentMode == 'custom') ...<Widget>[
                    const SizedBox(height: 14),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _currentCustomColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                      ),
                      title: const FitText('点击调色板挑选颜色'),
                      subtitle: FitText(
                        '当前色值：#${_currentCustomColor.value.toRadixString(16).substring(2).toUpperCase()}',
                        style: ts.bodySmall,
                      ),
                      trailing: const Icon(Icons.colorize),
                      onTap: _pickColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
