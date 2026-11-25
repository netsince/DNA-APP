/// 设置 → 更新设置（配置驱动版）。
///
/// ## 为什么「立即检查更新」是动作项
///
/// 它不改任何设置值，只是发起一次网络请求并弹窗/提示，属于 SettingAction 的
/// 定义域（没有 key 可写）。检查期间按钮要显示「正在检查…」并禁用，
/// 这需要本地状态，所以 builder 返回一个 StatefulWidget。
///
/// ## 为什么自动检查开关的副标题不再随值变化
///
/// 改动前它在「每次启动自动检查一次」与「已关闭,仅在你手动点击时检查」之间
/// 切换。声明层的 subtitle 是常量；用 SettingAction 换动态文案会让
/// `updateCheckEnabled` 丢掉 key（写通道管不到）。因此 subtitle 保留「开启」
/// 那句，关闭后的含义改用 hint 常驻说明。
library;

import 'package:material_ui/material_ui.dart';

import '../../services/update_service.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';
import 'update_dialog.dart';

const String _autoTitle = '启动时检查更新';
const String _autoSubtitle = '每次启动自动检查一次';
const String _autoHint = '关闭后仅在你手动点击时检查';

const String _checkTitle = '立即检查更新';
const String _checkSubtitle = '查询 GitHub 最新发布版本';
const String _checkingTitle = '正在检查…';

/// 手动检查一次：有新版就弹更新窗口，否则提示已是最新。
///
/// 只读发布信息，不下载、不安装（见 [UpdateService] 的设计说明）。
class _CheckNowTile extends StatefulWidget {
  const _CheckNowTile();

  @override
  State<_CheckNowTile> createState() => _CheckNowTileState();
}

class _CheckNowTileState extends State<_CheckNowTile> {
  final UpdateService _service = UpdateService();
  bool _checking = false;

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
    return SettingTile(
      icon: Icons.refresh,
      title: _checking ? _checkingTitle : _checkTitle,
      subtitle: _checkSubtitle,
      enabled: !_checking,
      onTap: _checkNow,
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

/// 更新设置页的完整声明。
final FieldsEntry updateCheckEntry = FieldsEntry(
  id: 'updateCheck',
  groupId: SettingsGroupId.about,
  icon: Icons.system_update_alt,
  title: '更新设置',
  subtitle: '启动时检查更新，也能手动检查',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'updateCheck.auto',
      icon: Icons.system_update_alt,
      title: '自动检查',
      description: '有新版时弹窗提示。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'updateCheck.updateCheckEnabled',
          title: _autoTitle,
          subtitle: _autoSubtitle,
          hint: _autoHint,
          key: 'updateCheckEnabled',
          defaultValue: true,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'updateCheck.manual',
      icon: Icons.wifi_tethering,
      title: '手动检查',
      description: '只读发布信息,不自动下载。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'updateCheck.checkNow',
          title: _checkTitle,
          subtitle: _checkSubtitle,
          builder: (BuildContext context, _) => const _CheckNowTile(),
        ),
      ],
    ),
  ],
);
