/// 设置 → 安全与隐私（配置驱动版）。
///
/// 本文件**取代**了此前的 security_settings_page.dart：页面只剩一份声明，
/// 没有 build、没有本地状态、没有 setState 镜像。
///
/// 行为对齐点（逐条对照旧页面）：
/// * 生物识别不可用时：两个开关隐藏，改为一行红色提示（旧页面的 _authAvailable 分支）。
/// * 三个开关的写入：`requireAuthForApp` / `requireAuthForArchive` 旧页面走
///   `saveAuthSettings(两个一起写)`，这里拆成各自独立的 key —— 写通道一次只改
///   一个字段，落盘结果等价（saveAuthSettings 本来也只是 copyWith 两个字段）。
/// * 「删除前需输入名称确认」的长说明拆成 subtitle + hint（旧页面是一整个
///   subtitle，超过 20 字，违反设置区文案规矩）。
library;

import 'package:flutter/material.dart';

import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';

/// 生物识别不可用时的提示行。
///
/// 单独抽成一个 builder，是为了让两个开关的 visibleWhen 保持纯声明式：
/// 可用性判断只在这里发生一次。
Widget _biometricUnavailableHint(BuildContext context) {
  return SettingHint(
    '当前设备或平台不支持生物识别验证',
    icon: Icons.info_outline,
    color: Theme.of(context).colorScheme.error,
  );
}

/// 安全与隐私页的完整声明。
final FieldsEntry securityEntry = FieldsEntry(
  id: 'security',
  groupId: SettingsGroupId.dataSecurity,
  icon: Icons.lock_outline,
  title: '安全与隐私',
  subtitle: '应用锁、删除前的二次确认',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'security.biometric',
      icon: Icons.fingerprint,
      title: '生物识别与密码保护',
      description: '用指纹、面容或锁屏密码保护隐私。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'security.biometricNotice',
          title: '生物识别不可用提示',
          searchable: false,
          visibleWhen: (SettingsRuntime r) => !r.biometricEnrolled,
          builder: (BuildContext context, _) =>
              _biometricUnavailableHint(context),
        ),
        SettingToggle(
          id: 'security.requireAuthForApp',
          title: '进入应用需验证',
          subtitle: '每次开启或从后台切回时验证身份',
          key: 'requireAuthForApp',
          visibleWhen: (SettingsRuntime r) => r.biometricEnrolled,
        ),
        SettingToggle(
          id: 'security.requireAuthForArchive',
          title: '查看归档需验证',
          subtitle: '访问归档内容前先验证身份',
          key: 'requireAuthForArchive',
          visibleWhen: (SettingsRuntime r) => r.biometricEnrolled,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'security.deleteGuard',
      icon: Icons.security_outlined,
      title: '防误触保护',
      description: '避免误删角色、世界或聊天记录。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'security.requireNameToDelete',
          title: '删除前需输入名称确认',
          subtitle: '开启时需完整输入要删除的目标名称',
          hint: '关闭后改为长按删除按钮 5 秒倒计时确认。',
          key: 'requireNameToDelete',
        ),
      ],
    ),
  ],
);
