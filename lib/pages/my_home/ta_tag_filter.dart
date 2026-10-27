import '../../models/ta.dart';

/// 「未分类」这一档的选择值。
///
/// 用一个不可能与真实标签冲突的哨兵串，表示「一个标签都没有的 TA」。
/// 真实标签里万一写了同样的串，[collectTags] 会把它丢掉（见下），
/// 所以这个哨兵不会被用户数据污染。
const String kUntaggedSelection = '\u0000untagged';

/// 把 TA 的标签数组规整成「去空白、去空串」的列表。
List<String> normalizeTagList(Iterable<String> raw) => <String>[
  for (final String t in raw)
    if (t.trim().isNotEmpty && t.trim() != kUntaggedSelection) t.trim(),
];

/// 收集一组 TA 里出现过的标签，按「用得多的在前」排序。
///
/// 次数相同时保持它们在列表里**首次出现**的先后 —— 列表本身已经按用户
/// 拖出来的顺序排好，所以同频标签的相对位置对用户是稳定的，不会每次
/// 打开都跳。
List<String> collectTags(List<TA> tas) {
  final Map<String, int> counts = <String, int>{};
  final Map<String, int> firstSeen = <String, int>{};
  for (final TA ta in tas) {
    for (final String tag in normalizeTagList(ta.tags)) {
      if (!counts.containsKey(tag)) {
        firstSeen[tag] = firstSeen.length;
      }
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final List<String> tags = counts.keys.toList();
  tags.sort((String a, String b) {
    final int byCount = counts[b]!.compareTo(counts[a]!);
    if (byCount != 0) return byCount;
    return firstSeen[a]!.compareTo(firstSeen[b]!);
  });
  return tags;
}

/// 列表里是否存在「一个标签都没有」的 TA（决定要不要给「未分类」入口）。
bool hasUntagged(List<TA> tas) =>
    tas.any((TA ta) => normalizeTagList(ta.tags).isEmpty);

/// 按当前选择过滤 TA。`null` = 全部。
///
/// 纯函数：不碰存储、不碰 UI，筛选规则可以在这里被穷举测试。
List<TA> filterTasByTag(List<TA> tas, String? selection) {
  if (selection == null) return tas;
  if (selection == kUntaggedSelection) {
    return tas.where((TA ta) => normalizeTagList(ta.tags).isEmpty).toList();
  }
  return tas
      .where((TA ta) => normalizeTagList(ta.tags).contains(selection))
      .toList();
}

/// 选择值是否仍然有效（对应标签消失 / 归档 / 被改标签时回落到「全部」）。
///
/// 不做「自动改写选择」这种副作用：选择是用户的意图，失效时**只是渲染成
/// 全部**，等他自己再点一次。避免在 build 里改状态引发连锁重建。
String? effectiveTagSelection(
  String? selection,
  List<String> availableTags, {
  required bool untaggedPresent,
}) {
  if (selection == null) return null;
  if (selection == kUntaggedSelection) {
    return untaggedPresent ? selection : null;
  }
  return availableTags.contains(selection) ? selection : null;
}
