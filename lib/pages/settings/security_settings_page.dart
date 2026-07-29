import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../state/app_controller.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _authForApp = false;
  bool _authForArchive = false;
  bool _authAvailable = false;
  bool _requireNameToDeleteTa = true;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _authForApp = s.requireAuthForApp;
    _authForArchive = s.requireAuthForArchive;
    _requireNameToDeleteTa = s.requireNameToDeleteTa;
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final a = await AuthService.canCheckBiometrics();
    if (mounted) setState(() => _authAvailable = a);
  }

  Future<void> _save() => widget.controller.saveAuthSettings(
    requireAuthForArchive: _authForArchive,
    requireAuthForApp: _authForApp,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全与隐私')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!_authAvailable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Text('当前设备不支持生物识别验证',
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ],
              ),
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('进入软件需验证'),
              subtitle: const Text('开启后每次进入应用或从后台切回都需要验证身份。'),
              value: _authForApp,
              onChanged: (v) { setState(() => _authForApp = v); _save(); },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('查看归档需验证'),
              subtitle: const Text('开启后进入任意归档页面需要验证身份。'),
              value: _authForArchive,
              onChanged: (v) { setState(() => _authForArchive = v); _save(); },
            ),
          ],
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('强制输入角色名以删除'),
            subtitle: const Text('删除角色卡前需完整输入角色名，并在 5 秒滚动确认中可反悔；关闭后改为长按右下角按钮 5 秒删除。'),
            value: _requireNameToDeleteTa,
            onChanged: (v) {
              setState(() => _requireNameToDeleteTa = v);
              widget.controller.saveRequireNameToDeleteTa(v);
            },
          ),
        ],
      ),
    );
  }
}
