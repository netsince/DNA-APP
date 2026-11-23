import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 编辑器「底部 sheet 表单」的**唯一骨架**。
///
/// 以前每个设置页各写一份 sheet：`Padding(bottom: viewInsets)` + SafeArea +
/// SingleChildScrollView + Column（标题 / 字段 / 取消·保存），连字段间距
/// （`hMd`）和按钮前的留白（`hXl`）都各抄一遍。现在只有这一份，页面只描述
/// 「标题 + 有哪些字段 + 提交时做什么」。
///
/// 语义（与旧手写 sheet 保持一致，别处不要再自行发挥）：
/// * 标题用 `titleLarge`，其后 [AppSpacing.hLg] 起字段；字段之间统一
///   [AppSpacing.hMd]，字段区与按钮行之间 [AppSpacing.hXl]；
/// * 键盘弹起时整张 sheet 跟着抬起（`viewInsets.bottom`），正在编辑的字段
///   不会被输入法遮住；
/// * 内容可滚动、底部留 SafeArea，字段多或键盘弹起时都还能滚到；
/// * 「保存」按钮**只回调** [onSubmit]：校验、错误落点与 pop 都归页面 ——
///   校验不通过时不能先关表单（就地 errorText，输入原样保留）；
/// * 「取消」直接 pop（不带返回值）。
///
/// 用法：
/// ```dart
/// FormSheet.show<QuickReply>(
///   context: context,
///   builder: (_) => _QuickReplySheet(existing: existing),
/// );
/// ```
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = '保存',
    this.cancelLabel = '取消',
  });

  /// sheet 标题（新增 / 编辑）。
  final String title;

  /// 字段区（通常是一串 `FormTextField` / `FormEntitySelect`）。
  /// 间距由本组件统一插入，页面不要再自己塞 `AppSpacing.hMd`。
  final List<Widget> children;

  /// 点「保存」时回调；校验与关闭表单由页面自己决定。
  final VoidCallback onSubmit;

  final String submitLabel;
  final String cancelLabel;

  /// 用统一的容器参数弹出表单（`isScrollControlled` + 拖拽把手）。
  ///
  /// 这两项原来两页各写一遍，留在页面里只会各自漂移（漏一个
  /// `isScrollControlled`，键盘弹起时 sheet 就会被压扁）。
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: builder,
    );
  }

  /// 字段之间插统一间距（首尾不插）。
  List<Widget> _fields() {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) out.add(AppSpacing.hMd);
      out.add(children[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      // 键盘避让：sheet 跟着输入法一起抬起，不遮住正在编辑的字段。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FitText(title, style: theme.textTheme.titleLarge),
              AppSpacing.hLg,
              ..._fields(),
              AppSpacing.hXl,
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: FitText(cancelLabel),
                    ),
                  ),
                  AppSpacing.wMd,
                  Expanded(
                    child: FilledButton(
                      onPressed: onSubmit,
                      child: FitText(submitLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
