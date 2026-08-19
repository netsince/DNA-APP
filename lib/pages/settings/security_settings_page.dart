// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import 'package:dna/widgets/fit_text.dart';

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('安全与隐私')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 身份验证保护 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.fingerprint, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('生物识别与密码保护', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '使用指纹、面容或系统锁屏密码保护应用隐私。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  if (!_authAvailable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.info_outline, size: 16, color: cs.error),
                          const SizedBox(width: 6),
                          FitText(
                            '当前设备或平台不支持生物识别验证',
                            style: TextStyle(color: cs.error, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else ...<Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const FitText('进入应用需验证'),
                      subtitle: const FitText('每次开启或从后台切回应用时验证身份'),
                      value: _authForApp,
                      onChanged: (v) {
                        setState(() => _authForApp = v);
                        _save();
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const FitText('查看归档需验证'),
                      subtitle: const FitText('访问已归档的角色、世界或对话列表时验证身份'),
                      value: _authForArchive,
                      onChanged: (v) {
                        setState(() => _authForArchive = v);
                        _save();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 删除确认防误触 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.security_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('防误触保护', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '防止误删角色、世界设定或聊天记录等重要数据。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('删除前需输入名称确认'),
                    subtitle: const FitText(
                      '开启时需完整输入要删除的目标名称；关闭后改为长按删除按钮 5 秒倒计时确认。',
                    ),
                    value: _requireNameToDelete,
                    onChanged: (v) {
                      setState(() => _requireNameToDelete = v);
                      widget.controller.saveRequireNameToDelete(v);
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
