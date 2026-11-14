import 'dart:io';

/// 启动耗时打点（仅在环境变量 DNA_STARTUP_TRACE=1 时生效，平时是空操作）。
///
/// 用途：定位「冷启动到出窗口」到底花在哪一段——引擎/DLL、Hive 初始化，
/// 还是首帧渲染。日志写到 %TEMP%\dna_startup.log，一行一个阶段。
class BootTrace {
  BootTrace._();

  static final Stopwatch _sw = Stopwatch()..start();

  static void mark(String stage) {
    if (Platform.environment['DNA_STARTUP_TRACE'] != '1') return;
    try {
      final File file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}dna_startup.log',
      );
      file.writeAsStringSync(
        '${_sw.elapsedMilliseconds}ms\t$stage\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 打点失败不影响启动
    }
  }
}
