import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dart 源码里不允许出现「被转义掉的插值」——即反斜杠后跟 $ 再跟左花括号。
///
/// ## 为什么要有这条测试
///
/// 这不是风格问题，是**字面量漏进界面**：批量改写 Dart 文件时若把 $ 当成需要
/// 转义的字符（像 shell / 正则那样）补一个反斜杠，编译器不会报错，插值直接不
/// 发生，用户看到的就是一串变量名。运行时想发现它得有人恰好点到那条提示。
///
/// 真实案例（v0.4.0 测试阶段，同一成因、两处）：
/// * lib/utils/action_table.dart —— 导出成功的提示条把插值原文显示给了用户
///   （本该是「已导出到：D:\\xxx.dnata」）；
/// * lib/pages/chat/chat_message_slice.dart —— token 缓存的 key 变成固定字符串，
///   所有附件的计数挤在同一个槽位上，缓存形同虚设。
///
/// 真要在界面上显示「$ 后跟 {」这几个字符，请写成常量或转义串，并在这里显式
/// 放行；不要让它悄悄变成常量。
void main() {
  test('lib 下没有把插值转义掉的字符串', () {
    // 转义后的插值开头 = 反斜杠 + $ + {。用码点拼出来，避免这条测试自己
    // 也命中自己（将来若把扫描范围扩到 test/）。
    final String marker = String.fromCharCodes(<int>[92, 36, 123]);
    final List<String> offenders = <String>[];

    for (final File file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final String path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains(marker)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些位置的插值不会发生，界面/缓存里会出现变量名原文：$offenders',
    );
  });
}
