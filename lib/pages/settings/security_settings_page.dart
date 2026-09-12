// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/platform_capabilities.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

/// 设置 → 安全与隐私。
///
/// 生物识别保护与实体删除二次确认设置。
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
  bool _requireNameToDelete = true;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _authForApp = s.requireAuthForApp;
    _authForArchive = s.requireAuthForArchive;
    _requireNameToDelete = s.requireNameToDelete;
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (!PlatformCapabilities.biometricAuthSupported) {
      if (mounted) setState(() => _authAvailable = false);
      return;
    }
    final a = await AuthService.canCheckBiometrics();
    if (mounted) setState(() => _authAvailable = a);
  }

  Future<void> _save() => widget.controller.saveAuthSettings(
        requireAuthForArchive: _authForArchive,
        requireAuthForApp: _authForApp,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('安全与隐私')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 身份验证保护 =====
          SettingSection(
            icon: Icons.fingerprint,
            title: '生物识别与密码保护',
            description: '使用指纹、面容或系统锁屏密码保护应用隐私。',
            children: <Widget>[
              if (!_authAvailable)
                SettingHint(
                  '当前设备或平台不支持生物识别验证',
                  icon: Icons.info_outline,
                  color: cs.error,
                )
              else ...<Widget>[
                SettingSwitch(
                  title: '进入应用需验证',
                  subtitle: '每次开启或从后台切回应用时验证身份',
                  value: _authForApp,
                  onChanged: (bool v) {
                    setState(() => _authForApp = v);
                    _save();
                  },
                ),
                SettingSwitch(
                  title: '查看归档需验证',
                  subtitle: '访问已归档的角色、世界或对话列表时验证身份',
                  value: _authForArchive,
                  onChanged: (bool v) {
                    setState(() => _authForArchive = v);
                    _save();
                  },
                ),
              ],
            ],
          ),

          // ===== 删除确认防误触 =====
          SettingSection(
            icon: Icons.security_outlined,
            title: '防误触保护',
            description: '防止误删角色、世界设定或聊天记录等重要数据。',
            children: <Widget>[
              SettingSwitch(
                title: '删除前需输入名称确认',
                subtitle: '开启时需完整输入要删除的目标名称；'
                    '关闭后改为长按删除按钮 5 秒倒计时确认。',
                value: _requireNameToDelete,
                onChanged: (bool v) {
                  setState(() => _requireNameToDelete = v);
                  widget.controller.saveRequireNameToDelete(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
