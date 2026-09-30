/// 全局统一的尺寸 token。
///
/// 各页面应复用这里的常量，避免圆角/内边距/间距数值散落各处造成观感不一致。
/// 后续若要整体调整风格，只需改这一处。
library;

/// 圆角（radius）。
const double kRadiusSm = 8; // 小：标签、徽章、输入框内部小块
const double kRadiusMd = 12; // 中：卡片、菜单项、网格卡
const double kRadiusLg = 16; // 大：重点大卡（余额卡、Hero 卡）

/// 页面左右内边距。
const double kPagePadding = 16;

/// 卡片 / 元素之间的统一间距。
const double kCardGap = 12;

/// 列表内分割 / 分组间距。
const double kListGap = 8;

/// 大屏内容最大宽度（设置页、登录页等居中内容的上限）。
const double kMaxContentWidth = 720;

/// 网格卡片（CardTile）的封面宽高比（3:4）。
const double kCardAspectRatio = 3 / 4;

/// 触底加载阈值（滚动距底部多少像素时触发加载更多）。
const double kLoadMoreThreshold = 400;
