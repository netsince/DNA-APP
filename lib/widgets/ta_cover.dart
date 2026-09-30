import 'package:dna/models/ta.dart';

/// 角色立绘的槽位与比例。
///
/// 编辑器里提示过三个槽位的用途:**square = 头像、landscape = 横版名片、
/// portrait = 全屏立绘**。所以:
///
/// * 展示页 hero 用 landscape(横版名片天生适合当大图头图);
/// * 瀑布流卡片按 **1:1 → 竖 → 横** 的优先级挑(用户指定):方图在网格里
///   最整齐,没有方图才退到竖图/横图。
///
/// 槽位同时决定卡片比例 —— 于是**不用解码图片**就知道该给多高,
/// 瀑布流排版不必等图片加载完成。
abstract final class TaCover {
  TaCover._();

  static const String square = 'square';
  static const String portrait = 'portrait';
  static const String landscape = 'landscape';

  /// 槽位 → 宽高比。
  static const Map<String, double> _ratios = <String, double>{
    square: 1.0,
    portrait: 9 / 16,
    landscape: 16 / 9,
  };

  /// 卡片优先级:1:1 → 竖 → 横。
  static const List<String> cardPriority = <String>[
    square,
    portrait,
    landscape,
  ];

  /// hero 优先级:竖版立绘 → 方图 → 横版名片。
  ///
  /// 竖版立绘天生适合当"人物大图"(手机壁纸比例),没有才退到方图/横图。
  static const List<String> heroPriority = <String>[
    portrait,
    square,
    landscape,
  ];

  /// 按优先级挑一个"确实有图"的槽位;一个都没有返回 null。
  static String? slotOf(TA? ta, {List<String> priority = cardPriority}) {
    if (ta == null) {
      return null;
    }
    for (final String slot in priority) {
      final String? ref = ta.images[slot];
      if (ref != null && ref.isNotEmpty) {
        return slot;
      }
    }
    return null;
  }

  /// 槽位对应的宽高比;没有立绘时按 1:1(首字占位卡)。
  static double ratioOf(String? slot) => _ratios[slot] ?? 1.0;
}
