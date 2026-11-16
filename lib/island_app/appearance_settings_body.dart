import 'package:flutter/material.dart';
import '../theme/tokens.dart';
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
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    ),
  );

  Widget _colorDot(Color color) {
    final selected = AppSettings.instance.accentColor == color.toARGB32();
    return InkWell(
      onTap: () {
        AppSettings.instance.setAccentColor(color.toARGB32());
        setState(() {});
      },
      borderRadius: BorderRadius.circular(AppRadius.lg),
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

  /// 自定义强调色取色器。
  ///
  /// 取色不是「需要立刻拍板的决定」，而是一段上下文内的调整：与同模块的
  /// 举报表单同一范式，用 bottom sheet 而不是全屏 AlertDialog（审计 3.2）。
  /// 取消/确定的语义与原来完全一致：拖动期间只改本地预览，点「确定」才写设置。
  Future<void> _pickColor() async {
    final current =
        AppSettings.instance.accentColor ?? _accentOptions.first.toARGB32();
    Color picked = Color(current);
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (bc, setSB) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '自定义强调色',
                    style: Theme.of(bc).textTheme.titleLarge,
                  ),
                  AppSpacing.hLg,
                  // 实时预览：色板本身在窄窗口里很小，给一块 44dp 实色 + 色值，
                  // 拖动时能直接看出最终会得到什么颜色。
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: picked,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(bc).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      AppSpacing.wMd,
                      Expanded(
                        child: Text(
                          _hexOf(picked),
                          style: Theme.of(bc).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: Theme.of(bc).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.hLg,
                  ColorPicker(
                    pickerColor: picked,
                    onColorChanged: (Color c) => setSB(() => picked = c),
                    enableAlpha: false,
                    labelTypes: const <ColorLabelType>[],
                    pickerAreaHeightPercent: 0.8,
                  ),
                  AppSpacing.hLg,
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('取消'),
                        ),
                      ),
                      AppSpacing.wMd,
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(true),
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      AppSettings.instance.setAccentColor(picked.toARGB32());
      setState(() {});
    }
  }

  /// 颜色 → #RRGGBB（只用于取色器里的预览文字，不参与存储）。
  String _hexOf(Color color) {
    final int rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final customColor = settings.accentColor == null
        ? null
        : Color(settings.accentColor!);
    const themeChoices = <Map<String, Object>>[
      {'value': ThemeMode.system, 'label': '跟随系统'},
      {'value': ThemeMode.light, 'label': '亮色'},
      {'value': ThemeMode.dark, 'label': '暗色'},
    ];
    return ListView(
      padding: AppInsets.card,
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
                  customColor?.toARGB32() ?? _accentOptions.first.toARGB32(),
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
