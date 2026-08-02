import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用图标切换服务。
///
/// 仅 Android 支持运行时切换启动图标（通过 activity-alias 启用/禁用实现）。
/// 其他平台（iOS / 桌面 / Web）操作系统不允许运行时更换图标，[isSupported] 为 false，
/// 调用 [setIcon] 会抛出 [UnsupportedError]。
class AppIconService {
  AppIconService._();

  static const MethodChannel _channel =
      MethodChannel('com.netsince.dna/app_icon');

  /// 当前平台是否支持运行时切换图标。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 可用的图标选项。
  static const List<AppIconOption> availableOptions = <AppIconOption>[
    AppIconOption.defaultIcon,
    AppIconOption.alternate,
    AppIconOption.renr,
    AppIconOption.gongzouchao,
    AppIconOption.yurugongzou,
    AppIconOption.zouchao,
    AppIconOption.zouhuan,
    AppIconOption.zoushen,
  ];

  /// 切换到指定图标。非 Android 平台会抛出 [UnsupportedError]。
  static Future<void> setIcon(AppIconOption option) async {
    if (!isSupported) {
      throw UnsupportedError('应用图标切换仅支持 Android 平台。');
    }
    await _channel.invokeMethod<void>(
      'setIcon',
      <String, String>{'name': option.alias},
    );
  }

  /// 根据 key 查找图标选项；未知 key 回退到默认图标。
  static AppIconOption optionForKey(String key) {
    for (final AppIconOption opt in availableOptions) {
      if (opt.key == key) return opt;
    }
    return AppIconOption.defaultIcon;
  }
}

/// 应用图标选项。
enum AppIconOption {
  /// 默认图标
  defaultIcon('default', '默认', 'assets/app_icon.png', 'MainActivityDefault'),

  /// 备用图标（用户提供的 PNG）
  alternate('alternate', '看板', 'assets/app_icon_alt.png', 'MainActivityAlt'),

  /// 新版可选图标
  gongzouchao('gongzouchao', '共奏潮', 'assets/icons/icon_gongzouchao.png',
      'MainActivityGongzouchao'),
  renr('renr', '人R', 'assets/icons/icon_renr.png', 'MainActivityRenr'),
  yurugongzou('yurugongzou', '与汝共奏:DNA', 'assets/icons/icon_yurugongzou.png',
      'MainActivityYurugongzou'),
  zouchao('zouchao', '奏潮', 'assets/icons/icon_zouchao.png', 'MainActivityZouchao'),
  zouhuan('zouhuan', '奏环', 'assets/icons/icon_zouhuan.png', 'MainActivityZouhuan'),
  zoushen('zoushen', '奏神', 'assets/icons/icon_zoushen.png', 'MainActivityZoushen');

  const AppIconOption(this.key, this.label, this.assetPath, this.alias);

  /// 持久化存储用的键。
  final String key;

  /// 设置页展示用的名称。
  final String label;

  /// 设置页预览用的资源路径。
  final String assetPath;

  /// Android activity-alias 名。
  final String alias;
}
