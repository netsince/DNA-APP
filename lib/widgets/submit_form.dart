import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../utils/error_display.dart';

/// 提交式表单的**收尾器**：草稿（[FormDraft]）负责字段，这里负责「一次性提交」。
///
/// 与设置区「改了就落盘」不同，这类表单是「填完一起提交」：
/// 进入忙态 → 跑一次 action → 失败把**原因**写进 [errorText]（就地显示，
/// 不再只弹一句「提交失败」）→ 成功后由调用方决定回填或 pop。
///
/// 代理配置 / 服务器地址 / 工单新建 / 积分兑换四处原来各写一份
/// `_saving` + try/catch/finally + snackbar，现在统一到这里。
class SubmitFormState extends ChangeNotifier {
  bool _busy = false;
  String? _errorText;

  /// 是否正在提交（按钮据此转圈并禁用）。
  bool get busy => _busy;

  /// 上一次提交失败的原因（成功或未提交时为 null）。
  String? get errorText => _errorText;

  void clearError() {
    if (_errorText == null) return;
    _errorText = null;
    notifyListeners();
  }

  /// 跑一次提交。返回是否成功。
  ///
  /// [errorPrefix] 是给人看的前缀（如「保存失败」），冒号后面接**真实原因**。
  /// [onFailure] 用于需要额外动作的调用方（比如失败后聚焦某个输入框）。
  Future<bool> run({
    required Future<void> Function() action,
    String errorPrefix = '提交失败',
    void Function(Object error)? onFailure,
  }) async {
    if (_busy) return false;
    _busy = true;
    _errorText = null;
    notifyListeners();
    try {
      await action();
      _busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _busy = false;
      _errorText = '$errorPrefix：${describeError(e)}';
      notifyListeners();
      onFailure?.call(e);
      return false;
    }
  }
}

/// 提交按钮：忙时转圈并禁用（占位尺寸不变，按钮不跳）。
class FormSubmitButton extends StatelessWidget {
  const FormSubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

/// 表单级错误横幅：把提交失败的原因就地显示在字段下方。
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message, this.padding});

  final String? message;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final String? text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 16, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
