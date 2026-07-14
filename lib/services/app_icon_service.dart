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

  static const String _defaultAlias = 'MainActivityDefault';
  static const String _altAlias = 'MainActivityAlt';

  /// 当前平台是否支持运行时切换图标。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 可用的图标选项。
  static const List<AppIconOption> availableOptions = <AppIconOption>[
    AppIconOption.defaultIcon,
    AppIconOption.alternate,
  ];

  /// 切换到指定图标。非 Android 平台会抛出 [UnsupportedError]。
  static Future<void> setIcon(AppIconOption option) async {
    if (!isSupported) {
      throw UnsupportedError('应用图标切换仅支持 Android 平台。');
    }
    final String alias =
        option == AppIconOption.defaultIcon ? _defaultAlias : _altAlias;
    await _channel.invokeMethod<void>(
      'setIcon',
      <String, String>{'name': alias},
    );
  }
}

/// 应用图标选项。
enum AppIconOption {
  /// 默认图标
  defaultIcon('default', '默认', 'assets/app_icon.png'),

  /// 备用图标（用户提供的 PNG）
  alternate('alternate', '看板', 'assets/app_icon_alt.png');

  const AppIconOption(this.key, this.label, this.assetPath);

  /// 持久化存储用的键。
  final String key;

  /// 设置页展示用的名称。
  final String label;

  /// 设置页预览用的资源路径。
  final String assetPath;
}
