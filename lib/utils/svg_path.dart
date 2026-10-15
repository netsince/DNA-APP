import 'dart:math' as math;
import 'dart:ui';

/// SVG path 的 d 属性 → Flutter [Path] 的解析器。
///
/// 覆盖 M m L l H h V v C c S s Q q T t A a Z z 全量命令。自己写而不是引
/// flutter_svg，是因为本项目只需要渲染少量单色路径图标（应用标、厂商标），
/// 不值得为它引入整套 SVG 渲染栈。
///
/// ## 参数必须逐字符扫描，不能「一把抓出所有数字」
///
/// 圆弧的 large-arc-flag 与 sweep-flag **各只占一个字符**，压缩写法会把它们连写：
/// 「a.797.797 0 00-.856 0」里的 00 是两个标志位（0 和 0），不是一个数 0。
/// 用「匹配数字」的办法去读，00 会被并成一个数，这条命令的参数就从 7 个变成 6 个，
/// 解析器只能提前结束它 —— **弧被整段丢掉，而且当前点不再更新**，后面所有相对
/// 命令都从错的地方起算，图形明显残缺。
///
/// 这个 bug 在真实数据上的规模：openai 丢 8 段弧、deepseek 丢 9 段、zhipu 丢 37 段
/// （anthropic 没有弧，所以不受影响）。所以这里改成 [_SvgNumberScanner] 顺序消费
/// 参数，标志位单独按字符读。
///
/// ## 坐标系
///
/// 内部一律以「已乘 [scale]」的坐标保存，返回的 [Path] 可直接画到 scale 倍的
/// 画布上（沿用项目原有实现的做法）。
Path parseSvgPath(
  String d, {
  double scale = 1,
  PathFillType fillType = PathFillType.nonZero,
}) {
  final _SvgPathBuilder builder =
      _SvgPathBuilder(scale: scale, fillType: fillType);
  builder.parse(d);
  return builder.path;
}

/// 诊断：d 里参数没被读完的命令（正常应为空）。
///
/// 这是「解析器有没有把源文件读对」的不变量：只要每条命令的参数都被恰好消费完，
/// 解析结果就忠实于源文件。上面的 00 标志位合并 bug 正是被它抓住的 ——
/// 见 test/svg_path_test.dart 的厂商标数据用例。
List<String> svgPathArgumentIssues(String d) {
  final _SvgPathBuilder builder = _SvgPathBuilder(scale: 1);
  builder.parse(d);
  return builder.issues;
}

/// 把 d 拆成「命令字母 + 参数串」的序列。
///
/// 命令字母表刻意不含 e / E，这样科学计数法（1e-5）会留在参数串里，
/// 不会被误当成新命令。
List<String> splitSvgCommands(String d) {
  final List<String> commands = <String>[];
  final RegExp regExp =
      RegExp(r'([MmZzLlHhVvCcSsQqTtAa])([^MmZzLlHhVvCcSsQqTtAa]*)');
  for (final RegExpMatch match in regExp.allMatches(d)) {
    commands.add(match.group(1)! + match.group(2)!);
  }
  return commands;
}

class _SvgPathBuilder {
  _SvgPathBuilder({required this.scale, this.fillType = PathFillType.nonZero});

  final double scale;
  final PathFillType fillType;
  final Path path = Path();
  final List<String> issues = <String>[];

  double _curX = 0;
  double _curY = 0;
  double _startX = 0;
  double _startY = 0;

  // 上一段三次曲线的第二控制点，用于 S / s 的反射。
  double? _cubicX;
  double? _cubicY;

  // 上一段二次曲线的控制点，用于 T / t 的反射。
  double? _quadX;
  double? _quadY;

  /// 每条命令的「一组参数」个数；参数总数必须是它的整数倍。
  static const Map<String, int> _arity = <String, int>{
    'M': 2, 'm': 2, 'L': 2, 'l': 2, 'H': 1, 'h': 1, 'V': 1, 'v': 1,
    'C': 6, 'c': 6, 'S': 4, 's': 4, 'Q': 4, 'q': 4, 'T': 2, 't': 2,
    'A': 7, 'a': 7, 'Z': 0, 'z': 0,
  };

  void parse(String d) {
    path.fillType = fillType;
    for (final String command in splitSvgCommands(d)) {
      final String type = command[0];
      final _SvgNumberScanner scanner =
          _SvgNumberScanner(command.substring(1));
      _apply(type, scanner);

      // 完整性判据：参数个数是「一组」的整数倍，且没有剩下的字符。
      // 两者任一不满足，说明这条命令的形状没被完整还原 —— 记下来供测试断言。
      // 只查「有没有剩余字符」不够：L 10（少一个 y）恰好把参数读完了，
      // 但只读到 1 个，仍是残缺的命令。
      final int arity = _arity[type] ?? 0;
      final bool incomplete = arity == 0
          ? !scanner.isDone
          : scanner.consumed % arity != 0 || !scanner.isDone;
      if (incomplete) issues.add(command);
    }
  }

  void _apply(String type, _SvgNumberScanner s) {
    switch (type) {
      case 'M':
      case 'm':
        bool first = true;
        while (true) {
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x == null || y == null) break;
          if (type == 'm') {
            _curX += x * scale;
            _curY += y * scale;
          } else {
            _curX = x * scale;
            _curY = y * scale;
          }
          if (first) {
            _startX = _curX;
            _startY = _curY;
            path.moveTo(_curX, _curY);
            first = false;
          } else {
            // M / m 之后多余的坐标对按 L / l 处理（SVG 规范）。
            path.lineTo(_curX, _curY);
          }
        }
        _cubicX = null;
        _quadX = null;
        break;

      case 'L':
      case 'l':
        while (true) {
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x == null || y == null) break;
          _curX = (type == 'l' ? _curX : 0) + x * scale;
          _curY = (type == 'l' ? _curY : 0) + y * scale;
          path.lineTo(_curX, _curY);
        }
        _cubicX = null;
        _quadX = null;
        break;

      case 'H':
      case 'h':
        while (true) {
          final double? x = s.nextNumber();
          if (x == null) break;
          _curX = (type == 'h' ? _curX : 0) + x * scale;
          path.lineTo(_curX, _curY);
        }
        _cubicX = null;
        _quadX = null;
        break;

      case 'V':
      case 'v':
        while (true) {
          final double? y = s.nextNumber();
          if (y == null) break;
          _curY = (type == 'v' ? _curY : 0) + y * scale;
          path.lineTo(_curX, _curY);
        }
        _cubicX = null;
        _quadX = null;
        break;

      case 'C':
      case 'c':
        while (true) {
          final double? x1 = s.nextNumber();
          final double? y1 = s.nextNumber();
          final double? x2 = s.nextNumber();
          final double? y2 = s.nextNumber();
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x1 == null ||
              y1 == null ||
              x2 == null ||
              y2 == null ||
              x == null ||
              y == null) {
            break;
          }
          // 相对命令的控制点以**本段起点**为基准，所以先取基准再更新当前点。
          final double bx = type == 'c' ? _curX : 0;
          final double by = type == 'c' ? _curY : 0;
          final double c1x = bx + x1 * scale;
          final double c1y = by + y1 * scale;
          final double c2x = bx + x2 * scale;
          final double c2y = by + y2 * scale;
          _curX = bx + x * scale;
          _curY = by + y * scale;
          path.cubicTo(c1x, c1y, c2x, c2y, _curX, _curY);
          _cubicX = c2x;
          _cubicY = c2y;
        }
        _quadX = null;
        break;

      case 'S':
      case 's':
        while (true) {
          final double? x2 = s.nextNumber();
          final double? y2 = s.nextNumber();
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x2 == null || y2 == null || x == null || y == null) break;
          // 首控制点 = 上一段第二控制点关于当前点的镜像；没有上一段则退化为当前点。
          final double c1x =
              _cubicX == null ? _curX : 2 * _curX - _cubicX!;
          final double c1y =
              _cubicY == null ? _curY : 2 * _curY - _cubicY!;
          final double bx = type == 's' ? _curX : 0;
          final double by = type == 's' ? _curY : 0;
          final double c2x = bx + x2 * scale;
          final double c2y = by + y2 * scale;
          _curX = bx + x * scale;
          _curY = by + y * scale;
          path.cubicTo(c1x, c1y, c2x, c2y, _curX, _curY);
          _cubicX = c2x;
          _cubicY = c2y;
        }
        _quadX = null;
        break;

      case 'Q':
      case 'q':
        while (true) {
          final double? x1 = s.nextNumber();
          final double? y1 = s.nextNumber();
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x1 == null || y1 == null || x == null || y == null) break;
          final double bx = type == 'q' ? _curX : 0;
          final double by = type == 'q' ? _curY : 0;
          final double c1x = bx + x1 * scale;
          final double c1y = by + y1 * scale;
          _curX = bx + x * scale;
          _curY = by + y * scale;
          path.quadraticBezierTo(c1x, c1y, _curX, _curY);
          _quadX = c1x;
          _quadY = c1y;
        }
        _cubicX = null;
        break;

      case 'T':
      case 't':
        while (true) {
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (x == null || y == null) break;
          final double c1x = _quadX == null ? _curX : 2 * _curX - _quadX!;
          final double c1y = _quadY == null ? _curY : 2 * _curY - _quadY!;
          _curX = (type == 't' ? _curX : 0) + x * scale;
          _curY = (type == 't' ? _curY : 0) + y * scale;
          path.quadraticBezierTo(c1x, c1y, _curX, _curY);
          _quadX = c1x;
          _quadY = c1y;
        }
        _cubicX = null;
        break;

      case 'A':
      case 'a':
        while (true) {
          final double? rx = s.nextNumber();
          final double? ry = s.nextNumber();
          final double? rotation = s.nextNumber();
          // 这两个必须按「单个字符」读，见文件头注释。
          final bool? largeArc = s.nextFlag();
          final bool? sweep = s.nextFlag();
          final double? x = s.nextNumber();
          final double? y = s.nextNumber();
          if (rx == null ||
              ry == null ||
              rotation == null ||
              largeArc == null ||
              sweep == null ||
              x == null ||
              y == null) {
            break;
          }
          final double rxs = rx * scale;
          final double rys = ry * scale;
          final double ex = (type == 'a' ? _curX : 0) + x * scale;
          final double ey = (type == 'a' ? _curY : 0) + y * scale;
          if (rxs == 0 || rys == 0) {
            // 半径为 0 的弧按直线处理（SVG 规范）。
            path.lineTo(ex, ey);
          } else {
            // 直接映射到 Flutter 自己的弧实现，不手写弧转贝塞尔。
            path.arcToPoint(
              Offset(ex, ey),
              radius: Radius.elliptical(rxs, rys),
              rotation: rotation * math.pi / 180,
              largeArc: largeArc,
              clockwise: sweep,
            );
          }
          _curX = ex;
          _curY = ey;
        }
        _cubicX = null;
        _quadX = null;
        break;

      case 'Z':
      case 'z':
        path.close();
        _curX = _startX;
        _curY = _startY;
        _cubicX = null;
        _quadX = null;
        break;
    }
  }
}

/// 顺序消费 path 命令参数的小扫描器。
class _SvgNumberScanner {
  _SvgNumberScanner(this.source);

  final String source;
  int _index = 0;

  /// 成功读出的参数个数（数字与标志位都算一个）。
  int consumed = 0;

  bool get isDone => _index >= source.length;

  static bool _isSeparator(int c) =>
      c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  void _skipSeparators() {
    while (_index < source.length && _isSeparator(source.codeUnitAt(_index))) {
      _index++;
    }
  }

  /// 读一个数（可带符号、小数、指数）；读不到返回 null 并回退。
  double? nextNumber() {
    _skipSeparators();
    final int start = _index;
    if (_index < source.length) {
      final int c = source.codeUnitAt(_index);
      if (c == 0x2B || c == 0x2D) _index++; // + -
    }
    bool sawDigit = false;
    while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
      _index++;
      sawDigit = true;
    }
    if (_index < source.length && source.codeUnitAt(_index) == 0x2E) {
      // 小数点。SVG 允许省略整数部分（.5）与分隔点（.5.5）。
      _index++;
      while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
        _index++;
        sawDigit = true;
      }
    }
    if (!sawDigit) {
      _index = start;
      return null;
    }
    if (_index < source.length) {
      final int c = source.codeUnitAt(_index);
      if (c == 0x65 || c == 0x45) {
        // e / E 指数；指数部分不完整就回退。
        final int save = _index;
        _index++;
        if (_index < source.length) {
          final int sign = source.codeUnitAt(_index);
          if (sign == 0x2B || sign == 0x2D) _index++;
        }
        bool sawExpDigit = false;
        while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
          _index++;
          sawExpDigit = true;
        }
        if (!sawExpDigit) _index = save;
      }
    }
    // SVG 允许省略整数部分（.5 / -.5），而 double.parse 不接受，补个 0。
    // 用 StringBuffer 而不是字符串相加，省得触发拼接字面量的 lint。
    final StringBuffer text = StringBuffer();
    String rest = source.substring(start, _index);
    if (rest.startsWith('.')) {
      text.write('0');
    } else if (rest.startsWith('-.') || rest.startsWith('+.')) {
      text.write(rest[0]);
      text.write('0');
      rest = rest.substring(1);
    }
    text.write(rest);
    consumed++;
    return double.parse(text.toString());
  }

  /// 读一个标志位：SVG 的 large-arc-flag / sweep-flag **各占一个字符**。
  ///
  /// 压缩写法会连写（00 表示两个 0、011 表示 0/1/1），所以只能逐字符读；
  /// 用数字规则去扫会把 00 并成一个数，参数整体错位。
  bool? nextFlag() {
    _skipSeparators();
    if (_index >= source.length) return null;
    final int c = source.codeUnitAt(_index);
    if (c == 0x30) {
      _index++;
      consumed++;
      return false;
    }
    if (c == 0x31) {
      _index++;
      consumed++;
      return true;
    }
    return null;
  }
}
