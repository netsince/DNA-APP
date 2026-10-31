import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 三态组件（空/错误/加载）必须**只有一份实现**。
///
/// ## 为什么要有这条测试
///
/// 这三个状态曾经各写各的：主程序只有 `AppEmptyState`，加载与错误靠散落的
/// `CircularProgressIndicator` 或手拼「图标+文字+重试」；社区另有一套
/// `EmptyState`/`ErrorState`/`LoadingState`（三态齐全、有 compact，但图标尺寸、
/// 间距、字号全是硬编码）。两边观感对不齐，就是这么来的。
///
/// 下沉到 `lib/widgets/state_views.dart` 之后，主程序的 `app_empty_state.dart`
/// 与社区的 `island_app/widgets/state_views.dart` 都只是 `export`/`typedef` 转发，
/// **不再有本地实现**。这条测试把那个状态钉住。
///
/// ## 注意 `FitText` 的连带影响
///
/// 下沉后空态标题从 `Text` 换成了 `FitText`（`FitText extends Text`，内部再渲染
/// 一个 `Text`）。因此断言文字时**不能用 `findsOneWidget`**，要用 `findsWidgets`
/// ——同一句话会命中 FitText 本身和它里面的 Text。
void main() {
  const String kImpl = 'lib/widgets/state_views.dart';

  List<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();

  String norm(String p) => p.replaceAll('\\', '/');

  test('lib 下只有一份三态组件实现', () {
    final List<String> offenders = <String>[];
    for (final File f in dartFiles()) {
      final String path = norm(f.path);
      if (path == kImpl) continue;
      for (final String line in f.readAsLinesSync()) {
        final String code = _stripComment(line);
        for (final String name in <String>[
          'AppEmptyState',
          'AppErrorState',
          'AppLoadingState',
        ]) {
          if (_declaresClass(code, name)) {
            offenders.add('$path: $name');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '三态组件只允许在 $kImpl 定义，其他地方只能 export/typedef：$offenders',
    );
  });

  test('社区不再自己定义三态组件（只用共享实现）', () {
    final List<String> offenders = <String>[];
    for (final File f in dartFiles()) {
      final String path = norm(f.path);
      if (!path.startsWith('lib/island_app/')) continue;
      for (final String line in f.readAsLinesSync()) {
        final String code = _stripComment(line);
        for (final String name in <String>[
          'EmptyState',
          'ErrorState',
          'LoadingState',
        ]) {
          if (_declaresClass(code, name)) {
            offenders.add('$path: $name');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: '社区出现了本地三态实现：$offenders');
  });

  test('两个转发文件都指向共享实现', () {
    final String mainEntry = File(
      'lib/widgets/app_empty_state.dart',
    ).readAsStringSync();
    expect(
      mainEntry.contains("export 'state_views.dart'"),
      isTrue,
      reason: '主程序 app_empty_state.dart 应当只做 export 转发',
    );

    final String islandEntry = File(
      'lib/island_app/widgets/state_views.dart',
    ).readAsStringSync();
    expect(
      islandEntry.contains("export 'package:dna/widgets/state_views.dart'"),
      isTrue,
      reason: '社区 state_views.dart 应当只做 export 转发',
    );
    for (final String alias in <String>[
      'EmptyState',
      'ErrorState',
      'LoadingState',
    ]) {
      expect(
        islandEntry.contains('typedef $alias ='),
        isTrue,
        reason: '社区短名 $alias 应当是 typedef 别名，不能是本地 class',
      );
    }
  });
}

/// 去掉行尾注释，避免注释里的 `class X` 造成误判。
String _stripComment(String line) {
  final int i = line.indexOf('//');
  return i < 0 ? line : line.substring(0, i);
}

/// 判断一行代码里是否**声明**了某个类。
///
/// 不用正则：`'class\s+'` 这类写法在字符串拼接里极易被转义吃掉
/// （`\s` 变成 `s`、`\b` 变成 `b`），正则静默失配、测试就成了永远通过的空壳。
/// 这里用最朴素的字符串判断，行为一眼可见。
bool _declaresClass(String code, String name) {
  final String needle = 'class $name';
  int from = 0;
  while (true) {
    final int i = code.indexOf(needle, from);
    if (i < 0) return false;
    final int end = i + needle.length;
    // 后面不能紧跟标识符字符，避免 'class EmptyStateX' 误判成 'class EmptyState'
    if (end >= code.length) return true;
    final String next = code[end];
    final bool isIdent = RegExp('[A-Za-z0-9_]').hasMatch(next);
    if (!isIdent) return true;
    from = end;
  }
}
