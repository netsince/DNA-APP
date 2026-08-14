import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'app_icon_page.dart';

/// 外观与体验 → 应用与启动
///
/// 应用图标、开场动画、主页导航与上下文 Token 仪表盘等应用级显示。
class AppearanceAppPage extends StatefulWidget {
  const AppearanceAppPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearanceAppPage> createState() => _AppearanceAppPageState();
}

class _AppearanceAppPageState extends State<AppearanceAppPage> {
  bool _showSplash = true;
  bool _showBottomNav = false;
  bool _showTokenDashboard = false;
  String _iconKey = 'default';
  final bool _iconSupported = AppIconService.isSupported || kIsWeb;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _showSplash = s.showSplashAnimation;
    _showBottomNav = s.showBottomNav;
    _showTokenDashboard = s.showTokenDashboard;
    _iconKey = s.appIcon;
  }

  AppIconOption get _currentIcon {
    for (final AppIconOption opt in AppIconService.availableOptions) {
      if (opt.key == _iconKey) return opt;
    }
    return AppIconOption.defaultIcon;
  }

  Future<void> _saveSplash() =>
      widget.controller.saveSplashAnimation(showSplashAnimation: _showSplash);

  Future<void> _saveBottomNav(bool v) =>
      widget.controller.saveShowBottomNav(v);

  Future<void> _saveTokenDashboard(bool v) =>
      widget.controller.saveShowTokenDashboard(v);

  Future<void> _restartOobe() async {
    await widget.controller.restartOobe();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('应用与启动')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('应用图标',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (!_iconSupported)
            FitText('当前平台不支持切换图标。',
                style: TextStyle(color: cs.error, fontSize: 12)),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AppIconPage(controller: widget.controller),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        _currentIcon.assetPath,
                        width: 64,
                        height: 64,
                        errorBuilder: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(Icons.android, size: 32, color: cs.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FitText(
                            '当前图标：${_currentIcon.label}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          FitText(
                            _iconSupported
                                ? (kIsWeb ? '点击更换浏览器标签页图标' : '点击更换启动器图标')
                                : '当前平台不支持切换',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('开场动画'),
            subtitle: const FitText('关闭后将直接进入应用，不再播放启动动画。'),
            value: _showSplash,
            onChanged: (v) {
              setState(() => _showSplash = v);
              _saveSplash();
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('主页底部导航栏'),
            subtitle: const FitText('开启后，在主页 / 群聊 / 我家 / 世界 底部显示导航栏，方便快速切换。默认关闭。'),
            value: _showBottomNav,
            onChanged: (v) {
              setState(() => _showBottomNav = v);
              _saveBottomNav(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('上下文 Token 实时仪表盘'),
            subtitle: const FitText('开启后，在聊天界面输入栏上方显示当前上下文 Token 占用与预算。默认关闭。'),
            value: _showTokenDashboard,
            onChanged: (v) {
              setState(() => _showTokenDashboard = v);
              _saveTokenDashboard(v);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: FitText('可重新进入首次启动引导流程。'),
          ),
          OutlinedButton.icon(
            onPressed: _restartOobe,
            icon: const Icon(Icons.restart_alt),
            label: const FitText('重新进入 OOBE'),
          ),
        ],
      ),
    );
  }
}
