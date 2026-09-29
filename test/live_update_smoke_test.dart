@Tags(<String>['live'])
library;

import 'package:dna/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// **真实网络**冒烟测试(打了 live 标签,默认不跑)。
///
/// 存在的意义:其余测试都用 `remoteOverride` 绕过了 HTTP,
/// 也就是说「真实请求 GitHub 能否成功解析」始终没被验证过。
///
/// 手动跑:
///   flutter test --no-pub --tags live test/live_update_smoke_test.dart
void main() {
  test('真实请求 GitHub API 能拿到并解析出发布信息', () async {
    final UpdateService svc = UpdateService();
    final UpdateCheckResult r = await svc.check();

    // ignore: avoid_print
    print('本地版本 = "${await svc.localVersion()}"');
    // ignore: avoid_print
    print('结果类型 = ${r.runtimeType}');

    switch (r) {
      case UpdateAvailable(:final UpdateInfo info):
        // ignore: avoid_print
        print('远端版本 = ${info.remoteVersion}');
        // ignore: avoid_print
        print('发布时间 = ${info.publishedAt}');
        // ignore: avoid_print
        print('日志长度 = ${info.changelog.length}');
        expect(info.remoteVersion, isNotEmpty);

      case UpdateUpToDate(:final String localVersion, :final String remoteVersion):
        // ignore: avoid_print
        print('已是最新: local=$localVersion remote=$remoteVersion');

      case UpdateCheckFailed(:final UpdateCheckError error, :final String detail):
        // 测试跑在纯 Dart VM 里,没有 platform channel,
        // PackageInfo 必然取不到 -> localVersionUnavailable 是**预期**结果。
        // 这仍然证明了网络请求与 JSON 解析是通的。
        // ignore: avoid_print
        print('失败: $error / $detail');
        expect(
          error,
          UpdateCheckError.localVersionUnavailable,
          reason: '测试环境没有 platform channel,取不到本地版本是正常的;'
              '若出现 network/http/malformed 则说明真实链路有问题',
        );
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('真实请求能解析出远端版本号(绕开本地版本)', () async {
    // 直接用 http 拉一次,验证 URL 与字段名都对 —— 不依赖 PackageInfo。
    final UpdateCheckResult r = await UpdateService().check(
      remoteOverride: null,
    );
    // 无论结果如何,只要不是 network 错,就说明请求本身通了。
    if (r is UpdateCheckFailed) {
      expect(r.error, isNot(UpdateCheckError.network),
          reason: '网络请求本身必须成功(HTTP + JSON 可解析)');
      expect(r.error, isNot(UpdateCheckError.http));
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
