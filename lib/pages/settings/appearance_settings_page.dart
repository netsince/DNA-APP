import 'package:flutter/material.dart';

import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  bool _showSplash = true;
  String _iconKey = 'default';
  String _themeMode = 'system';
  int _snackDurationMs = 1000;
  final bool _androidOk = AppIconService.isSupported;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _showSplash = s.showSplashAnimation;
    _iconKey = s.appIcon;
    _themeMode = s.themeMode;
    _snackDurationMs = s.snackDurationMs;
  }

  Future<void> _selectIcon(AppIconOption opt) async {
    if (_iconKey == opt.key) return;
    setState(() => _iconKey = opt.key);
    await widget.controller.saveAppIcon(opt);
    if (!mounted) return;
    showSnack(context, '应用图标已切换，返回桌面即可看到效果。');
  }

  Future<void> _saveSplash() =>
      widget.controller.saveSplashAnimation(showSplashAnimation: _showSplash);

  Future<void> _selectTheme(String mode) async {
    if (_themeMode == mode) {
      return;
    }
    setState(() => _themeMode = mode);
    await widget.controller.saveThemeMode(mode);
  }

  Future<void> _restartOobe() async {
    await widget.controller.restartOobe();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('外观与体验')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('应用图标', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (!_androidOk)
            Text('应用图标切换仅支持 Android 平台。', style: TextStyle(color: cs.error, fontSize: 12))
          else
            Text('选择启动器上显示的图标。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16, runSpacing: 12,
            children: AppIconService.availableOptions.map((AppIconOption opt) {
              return ChoiceChip(
                selected: _iconKey == opt.key,
                onSelected: _androidOk ? (_) => _selectIcon(opt) : null,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(opt.assetPath, width: 36, height: 36,
                          errorBuilder: (_, _, _) => const Icon(Icons.android)),
                    ),
                    const SizedBox(width: 10),
                    Text(opt.label),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text('主题', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('选择应用外观：跟随系统、始终亮色或始终暗色。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                label: Text(m['label']!),
                selected: _themeMode == m['value'],
                onSelected: (_) => _selectTheme(m['value']!),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开场动画'),
            subtitle: const Text('关闭后将直接进入应用，不再播放启动动画。'),
            value: _showSplash,
            onChanged: (v) { setState(() => _showSplash = v); _saveSplash(); },
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text('底部提示显示时长',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('控制复制、保存等操作底部提示（SnackBar）停留的时间。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _snackDurationMs.toDouble(),
                  min: 1000,
                  max: 10000,
                  divisions: 18,
                  label: '${(_snackDurationMs / 1000).toStringAsFixed(1)} 秒',
                  onChanged: (v) =>
                      setState(() => _snackDurationMs = v.round()),
                  onChangeEnd: (v) =>
                      widget.controller.saveSnackDuration(v.round()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: Text(
                  '${(_snackDurationMs / 1000).toStringAsFixed(1)} 秒',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('可重新进入首次启动引导流程。'),
          ),
          OutlinedButton.icon(
            onPressed: _restartOobe,
            icon: const Icon(Icons.restart_alt),
            label: const Text('重新进入 OOBE'),
          ),
        ],
      ),
    );
  }
}
