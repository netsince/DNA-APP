/// TA 性别的「值对象」。
///
/// ## 为什么 ID 是中文
///
/// 历史实现把 `'男' / '女' / '无性' / '其他'` 直接当持久化值与社区接口的值
/// （`ta.gender` 原样进 Hive、导出文件与发布 payload）。改 ID 就要迁存档与
/// 改服务端协议，成本远大于收益。
///
/// 所以这里**把既有中文值直接当作稳定 ID**：ID 不参与显示、不参与逻辑比较，
/// 只作为存储与协议的键。显示统一走 [labelOf] ——将来要出英文界面，只改
/// [label] 这一列即可，存档与协议一个字都不用动。
///
/// 与 `AppIconOption(key, label)` 是同一套思路：key 管身份，label 管显示。
///
/// ## 未知值不丢
///
/// 社区卡片的 gender 来自服务端，可能是任何字符串（外部导入、用户填的怪值）。
/// [labelOf] 对未知值**原样返回**，绝不替换成「未知」之类的词 —— 显示的职责
/// 是忠实呈现，不是纠正数据。
class TaGender {
  const TaGender._(this.id, this.label);

  /// 持久化 / 协议里的值。**不要拿来显示，也不要拿来做业务判断。**
  final String id;

  /// 界面显示文案。本地化时只改这里。
  final String label;

  static const TaGender male = TaGender._('男', '男');
  static const TaGender female = TaGender._('女', '女');
  static const TaGender agender = TaGender._('无性', '无性');
  static const TaGender other = TaGender._('其他', '其他');

  /// 选择器里的固定顺序（与历史下拉一致）。
  static const List<TaGender> selectable = <TaGender>[
    male,
    female,
    agender,
    other,
  ];

  /// 新建角色时的默认值（历史行为）。
  static const String fallbackId = '无性';

  /// 按 ID 精确匹配；未知值返回 null（调用方据此决定是「显示原文」还是「加一项」）。
  static TaGender? byId(String? id) {
    if (id == null) return null;
    for (final TaGender g in selectable) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// ID → 显示文案。
  ///
  /// * 已知 ID → 对应 label；
  /// * 未知 ID → 原样返回（不吞数据）；
  /// * null / 空串 → 空串（调用方约定：空串表示「不显示」）。
  static String labelOf(String? id) {
    if (id == null || id.isEmpty) return '';
    return byId(id)?.label ?? id;
  }

  /// 该 ID 是否是本应用认识的取值。
  static bool isKnown(String? id) => byId(id) != null;
}
