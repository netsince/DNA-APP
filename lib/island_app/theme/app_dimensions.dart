/// 社区侧的尺寸常量。
///
/// **本文件已改为对主程序令牌的转发**（`lib/theme/tokens.dart`），
/// 不再自己维护一套数值 ——两套常量各自演化，正是社区和主程序观感对不齐的根源。
///
/// 旧名保留只为不动既有调用点；新代码请直接用 `AppRadius` / `AppSpacing` / `AppSize`。
///
/// 注意旧名和主程序档位**不是同一套命名**，映射关系见每个常量的注释。
library;

import '../../theme/tokens.dart';

/// 圆角（小）—— 对应 `AppRadius.xs` = 8。
const double kRadiusSm = AppRadius.xs;

/// 圆角（中）—— 对应 `AppRadius.sm` = 12。
const double kRadiusMd = AppRadius.sm;

/// 圆角（大）—— 对应 `AppRadius.md` = 16。
const double kRadiusLg = AppRadius.md;

/// 页面左右内边距 —— 对应 `AppSpacing.lg` = 16。
const double kPagePadding = AppSpacing.lg;

/// 卡片 / 元素之间的统一间距 —— 对应 `AppSpacing.md` = 12。
const double kCardGap = AppSpacing.md;

/// 列表内分割 / 分组间距 —— 对应 `AppSpacing.sm` = 8。
const double kListGap = AppSpacing.sm;

/// 大屏内容最大宽度 —— 对应 `AppSize.editorMaxWidth` = 720。
const double kMaxContentWidth = AppSize.editorMaxWidth;

/// 网格卡片（CardTile）的封面宽高比（3:4）。
///
/// 这是业务比例不是设计令牌，主程序没有对应项，保留在社区。
const double kCardAspectRatio = 3 / 4;

/// 触底加载阈值（滚动距底部多少像素时触发加载更多）。
///
/// 这是交互参数不是视觉令牌，保留在社区。
const double kLoadMoreThreshold = 400;
