import 'package:flutter/material.dart';

/// 卡片列表的**响应式多列**排布:窗口够宽就并排多列,窄了自动回落单列。
///
/// ## 用在哪
///
/// 卡片型列表(群聊、身份):宽窗口下单列会把每张卡拉得很宽、
/// 一屏看不到几张,横向空间全浪费。够宽就并排,一屏多看好几张。
///
/// **不要用在拖拽排序列表**(会话、我家、世界):重排依赖线性
/// 列表(ReorderableListView),改成网格会丢掉拖拽排序能力,
/// 所以它们保持单列。
///
/// ## 列数怎么定
///
/// `列数 = (可用宽度 / [minItemWidth]).floor()`,再夹到
/// `[1], [maxColumns]]`;列数算下来是 1 时走原来的
/// [ListView.builder](惰性构建),多列时用 [Wrap] 排布
/// (多列场景下条目数通常有限,一次性构建可接受)。
class AppResponsiveWrap extends StatelessWidget {
  const AppResponsiveWrap({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.minItemWidth,
    this.maxColumns = 3,
    this.padding = const EdgeInsets.all(16),
    this.spacing = 12,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// 单张卡片的最小宽度(决定几列)。
  final double minItemWidth;

  /// 列数上限(窗口再宽也不会变成一排小格子)。
  final int maxColumns;

  final EdgeInsets padding;

  /// 卡片之间的横纵间距。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth - padding.horizontal;
        final int columns = available <= 0
            ? 1
            : (available / minItemWidth).floor().clamp(1, maxColumns);
        if (columns <= 1) {
          return ListView.builder(
            padding: padding,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          );
        }
        final double itemWidth =
            (available - spacing * (columns - 1)) / columns;
        return SingleChildScrollView(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: <Widget>[
              for (int i = 0; i < itemCount; i++)
                SizedBox(width: itemWidth, child: itemBuilder(context, i)),
            ],
          ),
        );
      },
    );
  }
}
