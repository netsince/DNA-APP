import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:dna/island_app/app_settings.dart';

/// 外观设置（主题 + 强调色 + 导航常驻）内容，无脚手架，由 [RootShell] 承载。
class AppearanceSettingsBody extends StatefulWidget {
  const AppearanceSettingsBody({super.key});

  @override
  State<AppearanceSettingsBody> createState() => _AppearanceSettingsBodyState();
}

class _AppearanceSettingsBodyState extends State<AppearanceSettingsBody> {
  static const List<Color> _accentOptions = <Color>[
    Colors.deepPurple,
    Colors.blue,
    Colors.indigo,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.pink,
    Colors.red,
  ];

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      );

  Widget _colorDot(Color color) {
    final selected = AppSettings.instance.accentColor == color.toARGB32();
    return InkWell(
      onTap: () {
        AppSettings.instance.setAccentColor(color.toARGB32());
        setState(() {});
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Future<void> _pickColor() async {
    final current =
        AppSettings.instance.accentColor ?? _accentOptions.first.toARGB32();
    Color picked = Color(current);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义强调色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const <ColorLabelType>[],
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      AppSettings.instance.setAccentColor(picked.toARGB32());
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final customColor =
        settings.accentColor == null ? null : Color(settings.accentColor!);
    const themeChoices = <Map<String, Object>>[
      {'value': ThemeMode.system, 'label': '跟随系统'},
      {'value': ThemeMode.light, 'label': '亮色'},
      {'value': ThemeMode.dark, 'label': '暗色'},
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _sectionTitle(context, '主题'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: themeChoices
              .map(
                (m) => ChoiceChip(
                  label: Text(m['label'] as String),
                  selected: settings.themeMode == m['value'],
                  onSelected: (_) {
                    settings.setThemeMode(m['value'] as ThemeMode);
                    setState(() {});
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        const Divider(),
        _sectionTitle(context, '强调色'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('自动'),
              selected: !settings.useCustomAccent,
              onSelected: (_) {
                settings.setAccentColor(null);
                setState(() {});
              },
            ),
            ChoiceChip(
              label: const Text('自定义'),
              selected: settings.useCustomAccent,
              onSelected: (_) {
                settings.setAccentColor(
                  customColor?.toARGB32() ??
                      _accentOptions.first.toARGB32(),
                );
                setState(() {});
              },
            ),
          ],
        ),
        if (settings.useCustomAccent) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _accentOptions.map(_colorDot).toList(),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: customColor ?? _accentOptions.first,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            title: const Text('自定义颜色'),
            subtitle: const Text('从色板中任意选取'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickColor,
          ),
        ],
      ],
    );
  }
}
