import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 内容列:窗口比 [maxWidth] 宽时**居中收窄成一列**,否则铺满。
///
/// ## 用在哪
///
/// **子页面**(聊天页、编辑器这类不在栏目壳里的页面):壳会统一算好
/// 内容列留白,子页面拿不到,所以用这个组件自己收窄,保证桌面宽窗口
/// 下正文/输入区不横跨整个屏幕。
///
/// 栏目页(首页/群聊/我家/身份/世界/设置)**不需要**用它——
/// [AppSectionShell] 已经按栏目的 `contentMaxWidth` 统一收窄了,
/// 并且标题栏与悬浮按钮都对齐同一条内容列。
///
/// 放在 Column 里时:高度无界则自动收缩到子组件高度(不会抢走
/// 兄弟 Expanded 的空间),有界则铺满,宽度始终按 [maxWidth] 收窄。
class AppContentFrame extends StatelessWidget {
  const AppContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AppSize.listMaxWidth,
  });

  final Widget child;

  /// 内容列最大宽度。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
