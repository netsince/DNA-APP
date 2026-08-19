// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'app_icon_page.dart';

/// 外观与体验 → 应用与启动。
///
/// 应用图标、开场动画、主页导航与记忆容量仪表盘等全局显示。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('应用与启动')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 应用图标 =====
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
                  FitText('应用图标', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FitText('自定义桌面或标签页展示的应用图标。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AppIconPage(controller: widget.controller),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              _currentIcon.assetPath,
                              width: 52,
                              height: 52,
                              errorBuilder: (_, _, _) => Container(
                                width: 52,
                                height: 52,
                                color: cs.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: Icon(Icons.android, size: 28, color: cs.outline),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                FitText(
                                  _currentIcon.label,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                FitText(
                                  _iconSupported
                                      ? (kIsWeb ? '点击更换浏览器标签页图标' : '点击更换桌面启动图标')
                                      : '当前平台不支持切换',
                                  style: ts.bodySmall?.copyWith(color: cs.outline),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 启动与全局交互 =====
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
                  FitText('启动与全局交互', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('开场启动动画'),
                    subtitle: const FitText('关闭后启动软件将直接进入主界面，跳过片头动画'),
                    value: _showSplash,
                    onChanged: (v) {
                      setState(() => _showSplash = v);
                      _saveSplash();
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('主页底部常驻导航栏'),
                    subtitle: const FitText('在屏幕底部常驻展示主页、群聊、我家、世界标签栏，方便单手切换'),
                    value: _showBottomNav,
                    onChanged: (v) {
                      setState(() => _showBottomNav = v);
                      _saveBottomNav(v);
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('聊天记忆容量仪表盘 (Token)'),
                    subtitle: const FitText('在聊天输入栏上方实时显示当前上下文 Token 占用进度与预算'),
                    value: _showTokenDashboard,
                    onChanged: (v) {
                      setState(() => _showTokenDashboard = v);
                      _saveTokenDashboard(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
