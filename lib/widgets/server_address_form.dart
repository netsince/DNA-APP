import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'config_status_banner.dart';
import 'fit_text.dart';

/// 服务器地址表单的主操作按钮形态。
enum ServerActionLayout {
  /// 内联在表单左侧、tonal 次要权重。
  ///
  /// OOBE 用：同屏页脚还有更强的「完成」，这里不该抢焦点。
  inlineTonal,

  /// 通栏实心。
  ///
  /// 社区的两个服务器地址设置页用：这是页面唯一的主操作。
  fullWidthFilled,
}

/// DNAISLAND 服务器地址输入 + 校验的通用表单。
///
/// 三处共用：OOBE 的「社区」步骤、设置页的「服务器地址」、社区的兜底设置页。
/// 三处原先各写一份，连「使用官方服务器」按钮的图标尺寸都不一致。
///
/// 表单只负责「输入 + 触发校验 + 展示结果」；校验与保存的副作用仍由调用方
/// 通过 [onSubmit] 实现 —— 因为三处的副作用本来就不同（OOBE 落盘并记状态、
/// 设置页落盘并弹 SnackBar、兜底页落盘后回调 onDone）。
class ServerAddressForm extends StatelessWidget {
  const ServerAddressForm({
    super.key,
    required this.controller,
    required this.defaultUrl,
    required this.onUseDefault,
    required this.onSubmit,
    this.checking = false,
    this.enabled = true,
    this.error,
    this.validated = false,
    this.validatedMessage = '连接验证成功。',
    this.actionLabel = '保存并检测',
    this.checkingLabel = '检测中...',
    this.actionIcon = Icons.verified_outlined,
    this.layout = ServerActionLayout.inlineTonal,
    this.onChanged,
  });

  /// 地址输入框控制器。
  final TextEditingController controller;

  /// 官方地址（hint 与「使用官方服务器」的目标值）。
  final String defaultUrl;

  /// 点「使用官方服务器」。
  final VoidCallback onUseDefault;

  /// 提交（校验 + 保存）。
  final VoidCallback onSubmit;

  /// 校验进行中。
  final bool checking;

  /// 是否可编辑（例如地址尚未从本地读出时置灰）。
  final bool enabled;

  /// 校验失败信息；非空时展示失败横幅。
  final String? error;

  /// 校验是否通过。
  final bool validated;

  /// 校验通过时的提示文案。
  final String validatedMessage;

  /// 主操作按钮文案。
  final String actionLabel;

  /// 校验进行中的按钮文案。
  final String checkingLabel;

  /// 主操作按钮图标。
  final IconData actionIcon;

  /// 主操作按钮形态。
  final ServerActionLayout layout;

  /// 输入变化回调（用来作废上一次校验结果）。
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool interactive = enabled && !checking;
    final Widget action = FilledButton.tonalIcon(
      onPressed: interactive ? onSubmit : null,
      icon: checking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(actionIcon),
      label: FitText(checking ? checkingLabel : actionLabel),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: controller,
          enabled: interactive,
          decoration: InputDecoration(
            labelText: '服务器地址',
            hintText: defaultUrl,
            prefixIcon: const Icon(Icons.dns_outlined),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onChanged: onChanged == null ? null : (_) => onChanged!(),
          onSubmitted: (_) {
            if (interactive) onSubmit();
          },
        ),
        AppSpacing.hSm,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: checking ? null : onUseDefault,
            icon: const Icon(Icons.public, size: AppSize.iconInline),
            label: const FitText('使用官方服务器'),
          ),
        ),
        AppSpacing.hSm,
        switch (layout) {
          ServerActionLayout.inlineTonal => Align(
            alignment: Alignment.centerLeft,
            child: action,
          ),
          ServerActionLayout.fullWidthFilled => SizedBox(
            width: double.infinity,
            child: action,
          ),
        },
        if (validated) ...<Widget>[
          AppSpacing.hMd,
          ConfigStatusBanner(message: validatedMessage),
        ],
        if (error != null) ...<Widget>[
          AppSpacing.hMd,
          ConfigStatusBanner(message: error!, isError: true),
        ],
      ],
    );
  }
}
