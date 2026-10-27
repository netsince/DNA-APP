import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import 'ta_tag_filter.dart';

/// 「我家」顶部的标签筛选条。
///
/// 只做一件事：把已有标签变成可点的筛选项。标签本身早就在 TA 模型里、
/// 编辑器里也早已能填，此前没有任何地方消费它 —— 这条筛选条就是那个
/// 消费入口。
///
/// 取舍：
/// * **单选**。多选交集会把「我现在只想看古风」变成一个集合运算，用户
///   没这个心智；需要精细查找还有搜索。
/// * 再点一次已选中的标签 = 取消筛选（等价于点「全部」），少一次抬手。
/// * 标签为空时不渲染本组件（调用方负责判断），页面上不会多出一条空条。
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({
    super.key,
    required this.tags,
    required this.selected,
    required this.untaggedPresent,
    required this.onSelect,
  });

  /// 已按「用得多的在前」排好序的标签。
  final List<String> tags;

  /// 当前选中项；null = 全部，[kUntaggedSelection] = 未分类。
  final String? selected;

  /// 是否存在没有任何标签的 TA（决定要不要给「未分类」入口）。
  final bool untaggedPresent;

  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      _chip('全部', null),
      for (final String tag in tags) _chip(tag, tag),
      if (untaggedPresent) _chip('未分类', kUntaggedSelection),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < chips.length; i++) ...<Widget>[
            if (i > 0) AppSpacing.wSm,
            chips[i],
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final bool isOn = selected == value;
    return ChoiceChip(
      label: FitText(label),
      selected: isOn,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      // 再点一次已选中的标签 ⇒ 取消筛选；点「全部」本来就是把选择置空。
      onSelected: (_) => onSelect(isOn && value != null ? null : value),
    );
  }
}
