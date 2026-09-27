import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 字体规范的静态约束(不启动 UI)。
///
/// 保护「内置思源黑体 + 真实字重 + 统一行高」这一组设计决定,
/// 防止后续开发重新引入系统字体依赖、合成加粗或手写行高。
void main() {
  group('字体规范', () {
    late String pubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
    });

    test('字体文件已进仓库且为有效 OTF', () {
      for (final String p in <String>[
        'assets/fonts/SourceHanSansSC-Regular.otf',
        'assets/fonts/SourceHanSansSC-Medium.otf',
      ]) {
        final File f = File(p);
        expect(f.existsSync(), isTrue, reason: '$p 不存在');

        // OpenType 字体魔数必须是 'OTTO'(CFF 轮廓)。
        final List<int> head = f.openSync().readSync(4);
        f.openSync().closeSync();
        expect(String.fromCharCodes(head), 'OTTO', reason: '$p 不是有效 OTF');
      }
    });

    test('pubspec 已注册字体族与两个字重', () {
      expect(pubspec.contains('family: SourceHanSans'), isTrue);
      expect(pubspec.contains('SourceHanSansSC-Regular.otf'), isTrue);
      expect(pubspec.contains('SourceHanSansSC-Medium.otf'), isTrue);
      expect(RegExp(r'weight:\s*400').hasMatch(pubspec), isTrue);
      expect(RegExp(r'weight:\s*500').hasMatch(pubspec), isTrue);
    });

    test('字体族名与令牌一致', () {
      final String tokens = File('lib/theme/tokens.dart').readAsStringSync();
      expect(tokens.contains("family = 'SourceHanSans'"), isTrue);
      expect(pubspec.contains('family: SourceHanSans'), isTrue);
    });

    test('OFL 许可证已随包分发', () {
      expect(File('LICENSE-OFL.txt').existsSync(), isTrue);
      expect(pubspec.contains('LICENSE-OFL.txt'), isTrue,
          reason: 'OFL 要求分发时附带许可证全文');
      final String lic = File('LICENSE-OFL.txt').readAsStringSync();
      expect(lic.contains('SIL Open Font License'), isTrue);
    });

    test('全项目不再使用 w600 / w700 / bold（合成加粗）', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e
          in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.path.endsWith('tokens.dart')) continue; // 令牌定义文件允许提及
        final String c = e.readAsStringSync();
        for (final String bad in <String>[
          'FontWeight.w600',
          'FontWeight.w700',
          'FontWeight.bold',
        ]) {
          if (c.contains(bad)) offenders.add('${e.path}: $bad');
        }
      }
      expect(offenders, isEmpty,
          reason: '内置字体只有 400/500 真实字重,粗体会触发合成加粗:\n'
              '${offenders.join('\n')}');
    });

    test('textTheme 每个槽位都显式定义了行高', () {
      final String main = File('lib/main.dart').readAsStringSync();
      final RegExpMatch? m = RegExp(r'static TextTheme _buildTextTheme')
          .firstMatch(main);
      expect(m, isNotNull);
      // 重映射段落应从 _buildTextTheme 开始到下一个顶层 } 结束。
      final String body = main.substring(m!.start, main.indexOf('\n}', m.start));
      // 11 个槽位应各自带上 height。
      final int heights = RegExp(r'height:\s*h(Title|Body|Reading)')
          .allMatches(body)
          .length;
      expect(heights, 11, reason: 'textTheme 有 11 个槽位,实际只找到 $heights 处 height');
    });

    test('行高令牌取值范围合理（中文正文需要比英文更宽松）', () {
      final String t = File('lib/theme/tokens.dart').readAsStringSync();
      expect(RegExp(r'title = 1\.\d+').hasMatch(t), isTrue);
      expect(RegExp(r'body = 1\.5\d*').hasMatch(t), isTrue,
          reason: '中文正文行高应 >= 1.5');
    });
  });
}
