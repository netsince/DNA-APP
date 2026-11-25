import 'package:material_ui/material_ui.dart';
import 'package:dna/widgets/fit_text.dart';

/// 底部提示（SnackBar）的兜底显示时长。
///
/// 1 秒只够"瞄一眼"：一句中文提示读完通常要 2~4 秒，短于这个量级的提示
/// 等于没有提示（审计 3.5「LLM 失败只弹 1 秒 snackbar」/ 4.3 无障碍）。
/// 实际时长仍由设置项 snackDurationMs 决定（见 AppController 初始化），
/// 这里只是**没人配置过**时的默认值，因此与设置项默认值保持一致。
/// 注意：必须与 AppSettings.snackDurationMs 的默认值（kDefaultSnackDurationMs，
/// models/app_settings.dart）保持一致 —— 那边是唯一默认值来源，这里是 UI 兜底；
/// 单边改动会让「没配置过」的用户看到两种时长。
const Duration kDefaultSnackDuration = Duration(milliseconds: 4000);

/// 底部提示（SnackBar）的默认显示时长，由设置项统一控制。
Duration _globalSnackDuration = kDefaultSnackDuration;

/// 更新全局底部提示的默认显示时长，供设置项统一控制。
void setSnackDuration(Duration duration) {
  _globalSnackDuration = duration;
}

void showSnack(
  BuildContext context,
  String message, {
  Duration? duration,
  SnackBarBehavior? behavior,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: FitText(message),
      duration: duration ?? _globalSnackDuration,
      behavior: behavior,
    ),
  );
}
