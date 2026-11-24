/// 表单「是否有未保存改动」的基线。
///
/// 三个编辑器表单（角色卡 / 世界 / 对话风格）各自维护一份基线，逻辑一模一样：
/// **挂载时拍一张快照，之后每次判断都与它比**；没有快照时一律算「没改过」
/// （刚挂载、还没拍到基线时不能报脏，否则一进页面就弹「放弃修改？」）。
///
/// 抽出来的是这条**规则**，不是存储方式：快照怎么序列化仍由各表单决定
/// （角色卡与世界用 `jsonEncode(toJson())`，对话风格用自定义指纹）。
class FormDirtyBaseline {
  String? _baseline;

  /// 拍一张新基线（挂载、导入回填、切换编辑对象后调用）。
  void capture(String snapshot) => _baseline = snapshot;

  /// 丢掉基线（表单卸载时）。
  void clear() => _baseline = null;

  /// 与基线不同即为「有改动」。**没有基线时返回 false**。
  bool hasChanged(String snapshot) =>
      _baseline != null && snapshot != _baseline;
}
