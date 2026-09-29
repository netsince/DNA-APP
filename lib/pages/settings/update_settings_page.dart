import 'package:flutter/material.dart';

import 'package:dna/services/update_service.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';
import 'update_dialog.dart';

/// 更新设置页。
///
/// 通过「高级 → 命令」输入 `setupdatepage` 进入。
///
/// 只包含一个开关:**启动时检查更新**。手动「检查更新」按钮也放在这里,
/// 方便关掉自动检查后仍能手查。
class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  final UpdateService _service = UpdateService();
  bool _checking = false;

  /// 手动检查一次,直接弹更新窗口或提示已是最新。
  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final UpdateCheckResult result = await _service.check();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result) {
      case UpdateAvailable(:final UpdateInfo info):
        await showUpdateDialog(context, info);
      case UpdateUpToDate():
        showSnack(context, '已是最新版本。');
      case UpdateCheckFailed(:final UpdateCheckError error):
        showSnack(context, '获取更新失败：${_errorLabel(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('更新设置')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: AppInsets.page,
            children: <Widget>[
              SettingSection(
                icon: Icons.system_update_alt,
                title: '自动检查',
                description: '有新版时弹窗提示。',
                children: <Widget>[
                  SettingSwitch(
                    title: '启动时检查更新',
                    subtitle: widget.controller.settings.updateCheckEnabled
                        ? '每次启动自动检查一次'
                        : '已关闭,仅在你手动点击时检查',
                    value: widget.controller.settings.updateCheckEnabled,
                    onChanged: (bool v) =>
                        widget.controller.saveUpdateCheckEnabled(v),
                  ),
                ],
              ),
              AppSpacing.hLg,
              SettingSection(
                icon: Icons.wifi_tethering,
                title: '手动检查',
                description: '只读发布信息,不自动下载。',
                children: <Widget>[
                  SettingTile(
                    icon: Icons.refresh,
                    title: _checking ? '正在检查…' : '立即检查更新',
                    subtitle: '查询 GitHub 最新发布版本',
                    enabled: !_checking,
                    onTap: _checkNow,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 把错误类型翻译成给用户看的话。
String _errorLabel(UpdateCheckError error) => switch (error) {
      UpdateCheckError.network => '网络连接失败,可能不是最新版',
      UpdateCheckError.http => '服务器返回异常,可能不是最新版',
      UpdateCheckError.malformed => '返回数据无法识别,可能不是最新版',
      UpdateCheckError.localVersionUnavailable => '读取本地版本号失败',
    };
