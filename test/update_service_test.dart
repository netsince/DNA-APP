import 'dart:convert';

import 'package:dna/pages/settings/update_dialog.dart';
import 'package:dna/services/update_service.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 更新检测的解析与渲染测试。
///
/// 用**真实抓取到的 GitHub 响应形状**做夹具,而不是自己编一个理想 JSON ——
/// 这样才能验证真实字段名(published_at / tag_name / body / html_url)。
void main() {
  group('UpdateService.parseRelease 字段解析', () {
    test('标准 release', () {
      final UpdateInfo info = UpdateService.parseRelease(<String, dynamic>{
        'tag_name': 'v0.2.1',
        'name': '0.2.1',
        'published_at': '2026-08-19T12:59:51Z',
        'body': '## v0.2.1\n\n主要更新：\n- 修了 A\n- 修了 B',
        'html_url': 'https://github.com/netsince/DNA-APP/releases/tag/v0.2.1',
      });

      expect(info.remoteVersion, '0.2.1');
      expect(info.changelog, contains('修了 A'));
      expect(info.publishedAt, isNotNull);
      expect(info.releaseUrl, contains('releases/tag/v0.2.1'));
    });

    test('tag 不规范也能解析出前几位', () {
      expect(
        UpdateService.parseRelease(<String, dynamic>{'tag_name': 'release-1.2.3'})
            .remoteVersion,
        '1.2.3',
      );
      expect(
        UpdateService.parseRelease(<String, dynamic>{'tag_name': 'v1.2.3-beta.1'})
            .remoteVersion,
        '1.2.3',
      );
    });

    test('tag 为空时退回 name', () {
      final UpdateInfo info = UpdateService.parseRelease(<String, dynamic>{
        'tag_name': '',
        'name': '2.0.0',
        'body': 'x',
      });
      expect(info.remoteVersion, '2.0.0');
    });

    test('缺 body / published_at 不崩', () {
      final UpdateInfo info = UpdateService.parseRelease(<String, dynamic>{
        'tag_name': 'v1.0.0',
      });
      expect(info.remoteVersion, '1.0.0');
      expect(info.changelog, '');
      expect(info.publishedAt, isNull);
    });

    test('tag 无法解析出数字 -> 抛 FormatException', () {
      expect(
        () => UpdateService.parseRelease(<String, dynamic>{'tag_name': 'latest'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('完全没有 tag/name -> 抛 FormatException', () {
      expect(
        () => UpdateService.parseRelease(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
    });

    test('真实响应(节选 netsince/DNA-APP v0.2.1)能解析', () {
      // 直接照抄线上抓到的关键字段。
      final Map<String, dynamic> raw = jsonDecode('''
      {
        "tag_name": "v0.2.1",
        "name": "0.2.1",
        "draft": false,
        "prerelease": false,
        "created_at": "2026-08-19T12:58:12Z",
        "published_at": "2026-08-19T12:59:51Z",
        "html_url": "https://github.com/netsince/DNA-APP/releases/tag/v0.2.1",
        "body": "## v0.2.1\\r\\n\\r\\nv0.2.1 现已发布。\\r\\n\\r\\n### 主要更新："
      }''') as Map<String, dynamic>;

      final UpdateInfo info = UpdateService.parseRelease(raw);
      expect(info.remoteVersion, '0.2.1');
      expect(info.publishedAt, isNotNull);
      expect(info.changelog, contains('现已发布'));
    });
  });

  group('check 的判定逻辑(remoteOverride,不走网络)', () {
    // 注意:check() 内部用 PackageInfo 取本地版本,测试环境下拿不到
    // (返回空串 -> 无法解析 -> Failed)。所以这里只断言**不崩、不误报**,
    // 真正的比较逻辑由 version_utils_test.dart 覆盖。
    test('远端版本可解析时不崩', () async {
      final UpdateCheckResult r = await UpdateService().check(
        remoteOverride: UpdateInfo(
          remoteVersion: '9.9.9',
          localVersion: '',
          changelog: '测试',
          publishedAt: DateTime(2026, 1, 1),
          releaseUrl: '',
        ),
      );
      expect(r, isA<UpdateCheckResult>());
    });

    test('远端不可解析 -> Failed,而不是误报有新版本', () async {
      final UpdateCheckResult r = await UpdateService().check(
        remoteOverride: const UpdateInfo(
          remoteVersion: 'latest',
          localVersion: '',
          changelog: '',
          publishedAt: null,
          releaseUrl: '',
        ),
      );
      expect(r, isA<UpdateCheckFailed>(),
          reason: '解析不了时宁可报失败,也不能提示「有新版本」骗用户去下载');
      // 本地版本也取不到时优先报 localVersionUnavailable;
      // 两者都属于「安全地失败」。
    });

    test('本地版本取不到时 -> localVersionUnavailable(启动检查会静默)',
        () async {
      final UpdateCheckResult r = await UpdateService().check(
        remoteOverride: const UpdateInfo(
          remoteVersion: '9.9.9',
          localVersion: '',
          changelog: '',
          publishedAt: null,
          releaseUrl: '',
        ),
      );
      // 测试环境 PackageInfo 抛异常 -> localVersion() 返回空串。
      expect(r, isA<UpdateCheckFailed>());
      expect(
        (r as UpdateCheckFailed).error,
        UpdateCheckError.localVersionUnavailable,
        reason: '这个错误类型让启动检查保持静默,'
            '否则用户每次启动都会看到自己无法解决的报错',
      );
    });
  });

  group('debugUpdateInfo(tryupdate 命令)', () {
    test('版本 999.999.999、日志「测试」、时间是传入的当前时间', () {
      final DateTime now = DateTime(2026, 9, 28, 15, 30);
      final UpdateInfo info = debugUpdateInfo(now);
      expect(info.remoteVersion, '999.999.999');
      expect(info.changelog, '测试');
      expect(info.publishedAt, now);
    });
  });

  group('更新弹窗渲染', () {
    Future<void> pump(WidgetTester t, UpdateInfo info) async {
      await t.pumpWidget(MaterialApp(home: UpdateDialog(info: info)));
      await t.pumpAndSettle();
    }

    /// `FitText extends Text` —— 直接匹配 `w is Text` 会把 FitText 和它
    /// 内部的 Text 都算上,导致 findsOneWidget 误报 findsNWidgets(2)。
    /// 这里只匹配内层真实 Text。
    Finder findText(String s) => find.byWidgetPredicate(
        (Widget w) => w is Text && w is! FitText && w.data == s);

    /// 更新日志用 SelectableText 渲染(可选中复制),单独匹配。
    Finder findSelectable(String s) =>
        find.byWidgetPredicate((Widget w) => w is SelectableText && w.data == s);

    testWidgets('必须显示版本号 / 发布时间 / 更新日志 / 两个按钮',
        (WidgetTester t) async {
      await pump(
        t,
        UpdateInfo(
          remoteVersion: '999.999.999',
          localVersion: '0.2.1',
          changelog: '测试',
          publishedAt: DateTime(2026, 9, 28, 15, 30),
          releaseUrl: '',
        ),
      );

      // 版本号(远端 + 本地)
      expect(findText('v999.999.999'), findsOneWidget);
      expect(findText('v0.2.1'), findsOneWidget);
      // 发布时间
      expect(findText('2026-09-28 15:30'), findsOneWidget);
      // 更新日志(用 SelectableText 渲染,可选中复制)
      expect(findSelectable('测试'), findsOneWidget);
      // 两个按钮
      expect(findText('前往更新'), findsOneWidget);
      expect(findText('忽略'), findsOneWidget);
    });

    testWidgets('日志为空时给出占位文案,不留空白', (WidgetTester t) async {
      await pump(
        t,
        const UpdateInfo(
          remoteVersion: '1.0.0',
          localVersion: '0.1.0',
          changelog: '   ',
          publishedAt: null,
          releaseUrl: '',
        ),
      );
      expect(findSelectable('(本次发布未提供更新日志)'), findsOneWidget);
      expect(findText('未知'), findsOneWidget, reason: '发布时间取不到应显示「未知」');
    });

    testWidgets('「忽略」能关掉弹窗', (WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => ElevatedButton(
            onPressed: () => showUpdateDialog(
              ctx,
              const UpdateInfo(
                remoteVersion: '1.0.0',
                localVersion: '0.1.0',
                changelog: 'x',
                publishedAt: null,
                releaseUrl: '',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(findText('open'));
      await t.pumpAndSettle();
      expect(findText('发现新版本'), findsOneWidget);

      await t.tap(findText('忽略'));
      await t.pumpAndSettle();
      expect(findText('发现新版本'), findsNothing);
    });
  });
}
