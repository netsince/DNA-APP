/// 版本号解析与比较。
///
/// ## 为什么需要容错解析
///
/// GitHub release 的 tag 写法不受控,可能是 `v1.2.3`、`release-1.2.3`、
/// `1.2.3-beta`、`ver1.2` 甚至 `1.2.3.4.5`。但**前几位一定是**
/// `{数字}.{数字}.{数字}`,所以策略是:
///
/// 1. 从字符串里**第一个数字**开始读;
/// 2. 依次读 `数字` + `.` + `数字` …,遇到**非数字也非点**的字符就**截断**;
/// 3. 得到的分段列表就是版本向量。
///
/// 例:
/// * `v0.2.1`        → `[0, 2, 1]`
/// * `0.2.1-beta`    → `[0, 2, 1]`(在 `-` 处截断)
/// * `release-1.2.3` → `[1, 2, 3]`(`release-` 被跳过,从第一个数字开始)
/// * `1.2`           → `[1, 2]`
/// * `1.2.3.4`       → `[1, 2, 3, 4]`
/// * `0.2.1+3`       → `[0, 2, 1]`(**build 号 `+3` 不计入比较**)
/// * `abc`           → `[]`(没有数字 → 无法解析)
///
/// ## 比较规则
///
/// 逐位比较,短的补 0。`[0,2,1]` vs `[0,2,1]` 相等;`[0,2]` vs `[0,2,0]`
/// 相等;`[0,2,1]` < `[0,3]`。
library;

/// 解析结果:版本向量 + 是否解析成功。
class ParsedVersion implements Comparable<ParsedVersion> {
  const ParsedVersion(this.parts, this.raw);

  /// 数字分段,如 `[0, 2, 1]`。
  final List<int> parts;

  /// 原始字符串(仅用于展示/调试)。
  final String raw;

  /// 一个数字都没读到 → 解析失败。
  bool get isValid => parts.isNotEmpty;

  /// 规范化展示:`0.2.1`。
  String get display => parts.join('.');

  @override
  int compareTo(ParsedVersion other) => compareParts(parts, other.parts);

  @override
  String toString() => '$display (raw: $raw)';
}

/// 逐位比较两个版本向量,短的补 0。
///
/// 返回负数表示 [a] 更旧,正数表示 [a] 更新,0 表示相等。
int compareParts(List<int> a, List<int> b) {
  final int n = a.length > b.length ? a.length : b.length;
  for (int i = 0; i < n; i++) {
    final int x = i < a.length ? a[i] : 0;
    final int y = i < b.length ? b[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// 把一个版本字符串解析成版本向量。
///
/// 容错规则见库注释。无法解析时返回的 [ParsedVersion.isValid] 为 false。
ParsedVersion parseVersion(String input) {
  final String s = input.trim();

  // 1. 跳过开头所有非数字字符,定位第一个数字("v"、"release-" 等前缀)。
  int i = 0;
  while (i < s.length && !_isDigit(s.codeUnitAt(i))) {
    i++;
  }
  if (i >= s.length) return ParsedVersion(const <int>[], s);

  // 2. 读 数字(.(数字)*)?,遇到既不是数字也不是点的字符就截断。
  final List<int> parts = <int>[];
  final StringBuffer cur = StringBuffer();
  bool stopped = false;

  for (; i < s.length && !stopped; i++) {
    final int c = s.codeUnitAt(i);
    if (_isDigit(c)) {
      cur.writeCharCode(c);
    } else if (c == 0x2E /* . */ ) {
      // 连续的点或前导点:`1..2` / `1.` —— 把当前段收尾,空段按 0 处理。
      parts.add(cur.isEmpty ? 0 : int.parse(cur.toString()));
      cur.clear();
    } else {
      // 非数字非点 → 截断,+aaa / -beta / 空格 / 下划线都在这里停下。
      stopped = true;
    }
  }
  // 收尾最后一段(只有真的读到过东西才收,避免 "1." 多加一个 0)。
  if (cur.isNotEmpty) parts.add(int.parse(cur.toString()));

  return ParsedVersion(parts, s);
}

/// 本地版本是否**低于**远端版本。
///
/// 只比 `x.y.z`,忽略 build 号(`+aaa`)—— 调用方传入前应已按需剥离,
/// 但 [parseVersion] 本身也会在 `+` 处截断。
///
/// 任一侧解析失败时返回 false(宁可不提示,也不要误报)。
bool isRemoteNewer(String local, String remote) {
  final ParsedVersion l = parseVersion(local);
  final ParsedVersion r = parseVersion(remote);
  if (!l.isValid || !r.isValid) return false;
  return l.compareTo(r) < 0;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
