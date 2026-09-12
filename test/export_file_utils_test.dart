import 'package:dna/services/export_file_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportFileUtils.friendlyTimestamp', () {
    test('格式为 YYYY_MM_DD_小时_分钟_秒 且补零', () {
      final String ts =
          ExportFileUtils.friendlyTimestamp(DateTime(2026, 9, 12, 23, 45, 8));
      expect(ts, '2026_09_12_23_45_08');
    });

    test('个位数月份/日期/时分秒均补零', () {
      final String ts =
          ExportFileUtils.friendlyTimestamp(DateTime(2026, 1, 2, 3, 4, 5));
      expect(ts, '2026_01_02_03_04_05');
    });
  });

  group('ExportFileUtils.buildFileName', () {
    final DateTime fixed = DateTime(2026, 9, 12, 23, 45, 8);

    test('角色卡:名称-友好时间.dnata', () {
      final String name = ExportFileUtils.buildFileName(
        name: '艾莲娜',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      expect(name, '艾莲娜-2026_09_12_23_45_08.dnata');
    });

    test('世界观:.dnaworld', () {
      final String name = ExportFileUtils.buildFileName(
        name: '中土世界',
        fallbackName: '世界',
        ext: 'dnaworld',
        now: fixed,
      );
      expect(name, '中土世界-2026_09_12_23_45_08.dnaworld');
    });

    test('身份:.dnapersona', () {
      final String name = ExportFileUtils.buildFileName(
        name: '旅人',
        fallbackName: '身份',
        ext: 'dnapersona',
        now: fixed,
      );
      expect(name, '旅人-2026_09_12_23_45_08.dnapersona');
    });

    test('名称为空时用兜底名(角色/世界/身份),不报错', () {
      expect(
        ExportFileUtils.buildFileName(
            name: '', fallbackName: '角色', ext: 'dnata', now: fixed),
        '角色-2026_09_12_23_45_08.dnata',
      );
      expect(
        ExportFileUtils.buildFileName(
            name: '   ', fallbackName: '世界', ext: 'dnaworld', now: fixed),
        '世界-2026_09_12_23_45_08.dnaworld',
      );
      expect(
        ExportFileUtils.buildFileName(
            name: '', fallbackName: '身份', ext: 'dnapersona', now: fixed),
        '身份-2026_09_12_23_45_08.dnapersona',
      );
    });

    test('过滤文件名非法字符', () {
      final String name = ExportFileUtils.buildFileName(
        name: r'a/b\c:d*e?f"g<h>i|j',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      expect(name, 'a_b_c_d_e_f_g_h_i_j-2026_09_12_23_45_08.dnata');
      expect(name.contains('/'), isFalse);
      expect(name.contains(r'\'), isFalse);
      expect(name.contains(':'), isFalse);
      expect(name.contains('*'), isFalse);
      expect(name.contains('?'), isFalse);
      expect(name.contains('"'), isFalse);
      expect(name.contains('<'), isFalse);
      expect(name.contains('>'), isFalse);
      expect(name.contains('|'), isFalse);
    });

    test('名称前后的空白被去除', () {
      final String name = ExportFileUtils.buildFileName(
        name: '  艾莲娜  ',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      expect(name, '艾莲娜-2026_09_12_23_45_08.dnata');
    });

    test('结尾的点与空格被去除(Windows 限制)', () {
      final String name = ExportFileUtils.buildFileName(
        name: '角色名... ',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      expect(name, '角色名-2026_09_12_23_45_08.dnata');
    });

    test('名称全为非法字符时回退到兜底名', () {
      final String name = ExportFileUtils.buildFileName(
        name: '///',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      // '///' -> '___' 非空,故保留过滤后的结果
      expect(name, '___-2026_09_12_23_45_08.dnata');
    });

    test('中文/emoji 等合法字符不过滤', () {
      final String name = ExportFileUtils.buildFileName(
        name: '艾莲娜·星语 🌙',
        fallbackName: '角色',
        ext: 'dnata',
        now: fixed,
      );
      expect(name, '艾莲娜·星语 🌙-2026_09_12_23_45_08.dnata');
    });
  });

  group('扩展名约定', () {
    test('三类扩展名均为小写', () {
      for (final String ext in <String>['dnata', 'dnaworld', 'dnapersona']) {
        expect(ext, ext.toLowerCase());
      }
    });
  });
}
