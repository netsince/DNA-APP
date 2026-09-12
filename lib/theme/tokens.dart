/// DNA 设计令牌(Design Tokens)。
///
/// 依据 `DESIGN_SPEC.md` 产出:把散落在各页面的 1000+ 处视觉魔数
/// 收敛为约 25 个具名常量,用于消除「同类元素在不同页面长得不一样」的问题。
///
/// 使用约定:
/// * 圆角一律用 [AppRadius],默认 [AppRadius.md]。
/// * 间距一律用 [AppSpacing],必须是 4 的倍数([AppSpacing.xxs] 为唯一例外)。
/// * 滚动页 `ListView.padding` 一律用 [AppInsets.page]。
/// * 卡片样式统一由 `ThemeData.cardTheme` 提供,业务代码只写 `Card(child: ...)`。
/// * 透明度只用 [AppAlpha] 四档。
/// * 颜色禁止硬编码,一律走 `ColorScheme`;遮罩用 [AppColors]。
library;

import 'package:flutter/material.dart';

/// 圆角令牌。
///
/// 现状曾有 13 种不同取值,收敛为 5 档。
abstract final class AppRadius {
  /// 8 —— 徽章、标签、小图标块、头像裁剪。
  static const double xs = 8;

  /// 12 —— 卡片内嵌的子卡片、图片槽。
  static const double sm = 12;

  /// 16 —— 主卡片(默认)。
  static const double md = 16;

  /// 20 —— 输入栏浮岛、大容器。
  static const double lg = 20;

  /// 999 —— 胶囊按钮、圆形。
  static const double pill = 999;

  /// [xs] 的 [BorderRadius]。
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));

  /// [sm] 的 [BorderRadius]。
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));

  /// [md] 的 [BorderRadius]。
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));

  /// [lg] 的 [BorderRadius]。
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));

  /// [pill] 的 [BorderRadius]。
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  /// 顶部两角圆角(如底部抽屉)。
  static const BorderRadius topRounded = BorderRadius.vertical(
    top: Radius.circular(md),
  );
}

/// 间距令牌(8pt 栅格)。
///
/// 现状曾有 21 种不同取值,收敛为 6 档。
abstract final class AppSpacing {
  /// 2 —— 图标与紧邻文字(唯一非 4 倍数的例外)。
  static const double xxs = 2;

  /// 4 —— 标题与副标题之间。
  static const double xs = 4;

  /// 8 —— 行内元素间隔、图标与文字。
  static const double sm = 8;

  /// 12 —— 列表项之间、分组内元素。
  static const double md = 12;

  /// 16 —— 卡片之间(默认)、卡片内边距。
  static const double lg = 16;

  /// 24 —— 模块分区间隔、页面上下留白。
  static const double xl = 24;

  // ---- 常用 SizedBox 快捷写法 ----

  /// 纵向 [xxs]。
  static const Widget hXxs = SizedBox(height: xxs);

  /// 纵向 [xs]。
  static const Widget hXs = SizedBox(height: xs);

  /// 纵向 [sm]。
  static const Widget hSm = SizedBox(height: sm);

  /// 纵向 [md]。
  static const Widget hMd = SizedBox(height: md);

  /// 纵向 [lg]。
  static const Widget hLg = SizedBox(height: lg);

  /// 纵向 [xl]。
  static const Widget hXl = SizedBox(height: xl);

  /// 横向 [sm]。
  static const Widget wSm = SizedBox(width: sm);

  /// 横向 [md]。
  static const Widget wMd = SizedBox(width: md);

  /// 横向 [lg]。
  static const Widget wLg = SizedBox(width: lg);
}

/// 页面级内边距令牌。
///
/// 现状 4 种 `EdgeInsets` 写法混用,收敛为 3 种。
abstract final class AppInsets {
  /// 所有滚动页 `ListView` 的默认内边距(h16 / v16)。
  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.lg,
  );

  /// 卡片内容内边距(all 16)。
  static const EdgeInsets card = EdgeInsets.all(AppSpacing.lg);

  /// 列表项内边距(h16 / v8)。
  static const EdgeInsets tile = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.sm,
  );

  /// 分组容器内边距(h16 / v4)。
  static const EdgeInsets group = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.xs,
  );
}

/// 阴影/高度令牌。
///
/// DNA 的视觉语言是「扁平 + 细描边」,而非阴影:默认一律 [flat]。
abstract final class AppElevation {
  /// 0 —— 默认:所有卡片(靠描边区分层级)。
  static const double flat = 0;

  /// 1 —— 浮动元素(输入栏、FAB)。
  static const double raised = 1;
}

/// 描边令牌。
abstract final class AppBorder {
  /// 卡片/分割线描边颜色(`outlineVariant` @ 0.5)。
  static Color color(ColorScheme cs) =>
      cs.outlineVariant.withValues(alpha: AppAlpha.subtle);

  /// 卡片描边(BorderSide)。
  static BorderSide card(ColorScheme cs) =>
      BorderSide(color: color(cs), width: 1);

  /// 卡片形状:圆角 [AppRadius.md] + 细描边。
  static RoundedRectangleBorder cardShape(ColorScheme cs) =>
      RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: card(cs),
      );

  /// 次级卡片形状:圆角 [AppRadius.sm] + 细描边。
  static RoundedRectangleBorder secondaryShape(ColorScheme cs) =>
      RoundedRectangleBorder(
        borderRadius: AppRadius.smAll,
        side: card(cs),
      );

  /// 分割线缩进(与列表项图标对齐)。
  static const double dividerIndent = 56;
}

/// 透明度令牌。
///
/// 现状 132 处 `withValues(alpha:)` 凭手感取值,收敛为 4 档。
abstract final class AppAlpha {
  /// 0.04 —— 极淡阴影、弱分隔。
  static const double faint = 0.04;

  /// 0.05 —— 卡片描边、弱背景。
  static const double subtle = 0.05;

  /// 0.5 —— 半透明遮罩、强调容器。
  static const double half = 0.5;

  /// 0.7 —— 次级文字。
  static const double muted = 0.7;

  /// 0.75 —— 次级文字(偏亮)。
  static const double mutedStrong = 0.75;
}

/// 尺寸令牌。
abstract final class AppSize {
  /// 行内小图标。
  static const double iconInline = 16;

  /// 卡片头图标。
  static const double iconCard = 20;

  /// 空状态图标。
  static const double iconEmpty = 48;

  /// 单行列表项高度。
  static const double tileSingle = 56;

  /// 双行列表项高度。
  static const double tileDouble = 72;

  /// 最小触摸目标。
  static const double touchTarget = 48;

  /// 聊天内容区最大宽度。
  static const double contentMaxWidth = 520;

  /// 设置页内容最大宽度。
  static const double settingsMaxWidth = 900;

  /// 横屏侧边栏宽度。
  static const double drawerWidth = 260;

  /// 头像尺寸(列表)。
  static const double avatarList = 44;

  /// 小图标块背景尺寸。
  static const double iconBox = 40;
}

/// 颜色令牌(仅限无法从 `ColorScheme` 取得的固定色)。
///
/// 除本类外,**禁止**出现 `Color(0xFF...)` 硬编码。
abstract final class AppColors {
  /// 品牌种子色(用于动态取色不可用时兜底)。
  static const Color seed = Color(0xFF147B74);

  /// 遮罩/浮层上的前景色。
  static const Color onScrim = Colors.white;

  /// 遮罩底色。
  static const Color scrim = Colors.black;

  /// 启动页背景(刻意固定为深色,不随明暗主题变化)。
  static const Color splashBackground = Color(0xFF1A1A1A);
}

/// 阴影令牌(全局唯一来源)。
abstract final class AppShadows {
  /// 柔和阴影:用于浮动元素与消息气泡。
  static const List<BoxShadow> soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A000000), // black @ 0.04
      blurRadius: 6,
      offset: Offset(0, 1.5),
    ),
  ];
}
