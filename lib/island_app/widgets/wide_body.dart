import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

///社区页面的「版心」：宽窗口下把内容**居中收窄**成一列。
///
/// ##为什么需要它
///
///主程序的版心由栏目壳统一给（`SectionPageData.contentMaxWidth` + `_contentInset`），
///页面自己不用管。但社区这一栏是 `contentMaxWidth: double.infinity`（岛自带完整
///外壳，按整窗宽设计），**壳不再替它收窄** ——于是茶馆、文章、公告这些单列页面
///在桌面上会拉成一条横跨1920px的文字，行长完全不可读。
///
///这个组件把「版心」这件事故意做成**一个可复用的零件**，让社区各页不必各自
///写一遍 `Center + ConstrainedBox`（那正是现在 `sponsor_body`里那份内联实现）。
///
/// ##取值
///
///数值全部复用主程序的 [AppSize]令牌，不引入第二套常量：
/// * [WideContent.reading] ——长文本（帖子、文章、公告）。760，和消息列表同宽；
/// * [WideContent.list] ——一般列表（世界、通知、积分、处罚）。760；
/// * [WideContent.form] ——表单/设置类。720（与岛上原有 kMaxContentWidth一致）；
/// * [WideContent.grid] ——网格页（生图、卡片墙）。1040，和「我家」同宽。
enum WideContent {
  reading(AppSize.listMaxWidth),
  list(AppSize.listMaxWidth),
  form(720),
  grid(AppSize.cardGridMaxWidth);

  const WideContent(this.maxWidth);

  final double maxWidth;
}

///居中收窄到 [kind]对应的版心宽度；窗口更窄时铺满（行为与主程序壳一致）。
class WideBody extends StatelessWidget {
  const WideBody({
    super.key,
    required this.child,
    this.kind = WideContent.list,
  });

  final Widget child;
  final WideContent kind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: kind.maxWidth),
        child: child,
      ),
    );
  }
}

///可用宽度大于版心时，两侧应留的空白（纯函数，便于单测）。
///
///用于**滚动视图内部**的收窄：`CustomScrollView` / `ListView`不能直接包
/// `ConstrainedBox`（那会破坏滚动与 `Sliver`布局），正确做法是把多余的宽度
///变成左右留白（`SliverPadding` / `padding`），滚动行为完全不变。
double wideInset(double availableWidth, {required double maxWidth}) {
  if (!availableWidth.isFinite || availableWidth <= maxWidth) return 0;
  return (availableWidth - maxWidth) / 2;
}

///按可用宽度算网格列数（纯函数，便于单测）。
///
///规则：每列至少 [minColumnWidth]，列数夹在 [minColumns]..[maxColumns]。
///桌面上「硬编码 crossAxisCount:2」是社区生图页最刺眼的问题 ——
///1920宽时每张图接近950px。
int gridColumnsFor(
  double availableWidth, {
  double minColumnWidth = 240,
  int minColumns = 2,
  int maxColumns = 6,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) return minColumns;
  final int raw = (availableWidth / minColumnWidth).floor();
  if (raw < minColumns) return minColumns;
  if (raw > maxColumns) return maxColumns;
  return raw;
}
