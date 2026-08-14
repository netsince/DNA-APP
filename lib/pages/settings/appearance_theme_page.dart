import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 外观与体验 → 主题与颜色
///
/// 应用主题模式与强调色（自动 / 自定义）。
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
        title: const FitText('选择强调色'),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('主题与颜色')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('主题',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText('选择应用外观：跟随系统、始终亮色或始终暗色。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <Map<String, String>>[
              <String, String>{'value': 'system', 'label': '跟随系统'},
              <String, String>{'value': 'light', 'label': '亮色'},
              <String, String>{'value': 'dark', 'label': '暗色'},
            ].map((Map<String, String> m) {
              return ChoiceChip(
                label: FitText(m['label']!),
                selected: _themeMode == m['value'],
                onSelected: (_) => _selectTheme(m['value']!),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          FitText('强调色',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
              '自动：主界面跟随系统取色，聊天界面使用角色卡图片的主色。\n自定义：统一使用你指定的颜色。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <Map<String, String>>[
              <String, String>{'value': 'auto', 'label': '自动'},
              <String, String>{'value': 'custom', 'label': '自定义'},
            ].map((Map<String, String> m) {
              return ChoiceChip(
                label: FitText(m['label']!),
                selected: _accentMode == m['value'],
                onSelected: (_) => _selectAccentMode(m['value']!),
              );
            }).toList(),
          ),
          if (_accentMode == 'custom') ...<Widget>[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _currentCustomColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
              title: const FitText('自定义颜色'),
              subtitle: const FitText('点击选择强调色'),
              onTap: _pickColor,
            ),
          ],
        ],
      ),
    );
  }
}
