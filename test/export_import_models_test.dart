import 'dart:convert';

import 'package:dna/models/ta.dart';
import 'package:dna/services/data_backup_models.dart';
import 'package:dna/services/data_backup_service.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportedImageInfo 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const ExportedImageInfo img = ExportedImageInfo(
        data: 'data:image/png;base64,AAAA',
        width: 100,
        height: 200,
        fx: 'fx-1',
        dataverification: 'dv-1',
      );
      final ExportedImageInfo back = ExportedImageInfo.fromJson(img.toJson());
      expect(back.data, img.data);
      expect(back.width, img.width);
      expect(back.height, img.height);
      expect(back.fx, img.fx);
      expect(back.dataverification, img.dataverification);
    });

    test('data 为 null 时安全往返', () {
      const ExportedImageInfo img = ExportedImageInfo(data: null);
      final ExportedImageInfo back = ExportedImageInfo.fromJson(img.toJson());
      expect(back.data, isNull);
    });
  });

  group('ExportedCharacter 序列化', () {
    test('toJson / fromJson 往返一致', () {
      final ExportedCharacter c = ExportedCharacter(
        id: 'ta-1',
        name: '艾莉',
        gender: '女',
        persona: 'p',
        intro: 'i',
        opening: 'o',
        tags: <String>['t1', 't2'],
        dialogueStyle: const <Map<String, String>>[
          <String, String>{'user': 'u', 'assistant': 'a'},
        ],
        images: const <String, ExportedImageInfo>{
          'square': ExportedImageInfo(data: 'data:image/png;base64,AA'),
        },
      );
      final ExportedCharacter back = ExportedCharacter.fromJson(c.toJson());
      expect(back.id, c.id);
      expect(back.name, c.name);
      expect(back.gender, c.gender);
      expect(back.persona, c.persona);
      expect(back.intro, c.intro);
      expect(back.opening, c.opening);
      expect(back.tags, c.tags);
      expect(back.dialogueStyle, c.dialogueStyle);
      expect(back.images['square']!.data, 'data:image/png;base64,AA');
    });

    test('缺失字段使用默认值而非抛异常', () {
      final ExportedCharacter back =
          ExportedCharacter.fromJson(<String, dynamic>{'id': 'x'});
      expect(back.id, 'x');
      expect(back.name, '');
      expect(back.gender, '无性');
      expect(back.tags, isEmpty);
      expect(back.images, isEmpty);
    });

    test('toTA 还原基础字段与对话风格', () {
      final ExportedCharacter c = ExportedCharacter(
        id: 'ta-2',
        name: '鲍勃',
        gender: '男',
        persona: 'p2',
        intro: 'i2',
        opening: 'o2',
        tags: <String>['z'],
        dialogueStyle: const <Map<String, String>>[
          <String, String>{'user': 'u', 'assistant': 'a'},
        ],
        images: const <String, ExportedImageInfo>{},
      );
      final TA ta = c.toTA();
      expect(ta.id, 'ta-2');
      expect(ta.name, '鲍勃');
      expect(ta.gender, '男');
      expect(ta.persona, 'p2');
      expect(ta.tags, <String>['z']);
      expect(ta.dialogueStyle, hasLength(1));
      expect(ta.dialogueStyle.first.user, 'u');
      expect(ta.dialogueStyle.first.assistant, 'a');
    });

    test('toTA 透传 protection 溯源包', () {
      final ExportedCharacter c = ExportedCharacter(
        id: 'ta-3',
        name: 'C',
        gender: '女',
        persona: '',
        intro: '',
        opening: '',
        tags: const <String>[],
        dialogueStyle: const <Map<String, String>>[],
        images: const <String, ExportedImageInfo>{},
      );
      final TA ta = c.toTA(protection: <String, dynamic>{
        'originalLink': 'https://example.com/ta',
      });
      expect(ta.protection?['originalLink'], 'https://example.com/ta');
    });
  });

  group('ExportPackage 溯源字段透传（不编不改）', () {
    test('toJson / fromJson 完整保留 protection 与图片槽溯源', () {
      final ExportPackage pkg = ExportPackage(
        version: 1,
        exportType: 'single',
        exportedAt: '2026-01-01T00:00:00Z',
        compressed: true,
        character: ExportedCharacter(
          id: 'ta-4',
          name: 'D',
          gender: '女',
          persona: '',
          intro: '',
          opening: '',
          tags: const <String>[],
          dialogueStyle: const <Map<String, String>>[],
          images: const <String, ExportedImageInfo>{
            'square': ExportedImageInfo(
              data: 'data:image/png;base64,AA',
              fx: 'FX1',
              dataverification: 'DV1',
            ),
          },
        ),
        protection: <String, dynamic>{
          'originalLink': 'https://example.com/orig',
          '_lk': 'lk-token',
          'Tips': 'some-tips',
          'images': <String, dynamic>{
            'square': <String, dynamic>{'fx': 'FX1', 'dataverification': 'DV1'},
          },
        },
      );

      final Map<String, dynamic> json = pkg.toJson();
      // toJson 应将图片槽溯源注入 character.images[slot]
      final Map<String, dynamic> charImages =
          (json['character'] as Map<String, dynamic>)['images'] as Map<String, dynamic>;
      expect(charImages['square']['fx'], 'FX1');
      expect(charImages['square']['dataverification'], 'DV1');
      expect(json['originalLink'], 'https://example.com/orig');
      expect(json['_lk'], 'lk-token');
      expect(json['Tips'], 'some-tips');

      final ExportPackage back = ExportPackage.fromJson(json);
      // fromJson 应把 character.images 的图片槽溯源读回 protection
      final Map<String, dynamic> backImages =
          back.protection!['images'] as Map<String, dynamic>;
      expect(backImages['square']['fx'], 'FX1');
      expect(backImages['square']['dataverification'], 'DV1');
      expect(back.protection!['originalLink'], 'https://example.com/orig');
      expect(back.protection!['_lk'], 'lk-token');
      expect(back.protection!['Tips'], 'some-tips');
      expect(back.character.images['square']!.fx, 'FX1');
    });

    test('无 protection 时 toJson 不含溯源字段', () {
      final ExportPackage pkg = ExportPackage(
        version: 1,
        exportType: 'single',
        exportedAt: 't',
        compressed: false,
        character: ExportedCharacter(
          id: 'ta-5',
          name: 'E',
          gender: '女',
          persona: '',
          intro: '',
          opening: '',
          tags: const <String>[],
          dialogueStyle: const <Map<String, String>>[],
          images: const <String, ExportedImageInfo>{},
        ),
      );
      final Map<String, dynamic> json = pkg.toJson();
      expect(json.containsKey('originalLink'), isFalse);
      expect(json.containsKey('_lk'), isFalse);
      expect(json.containsKey('Tips'), isFalse);
      final ExportPackage back = ExportPackage.fromJson(json);
      expect(back.protection, isNull);
    });
  });

  group('DataBackupManifest 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const DataBackupManifest m = DataBackupManifest(
        version: 1,
        exportedAt: '2026',
        app: 'dna-client',
        type: 'conversations',
      );
      final DataBackupManifest back = DataBackupManifest.fromJson(m.toJson());
      expect(back.version, m.version);
      expect(back.exportedAt, m.exportedAt);
      expect(back.app, m.app);
      expect(back.type, m.type);
    });

    test('缺失 type 时默认 full', () {
      final DataBackupManifest back = DataBackupManifest.fromJson(<String, dynamic>{
        'version': 1,
        'exportedAt': 'x',
        'app': 'a',
      });
      expect(back.type, 'full');
    });
  });

  group('DataImportReport 持有导入统计', () {
    test('字段正确暴露', () {
      const DataImportReport r = DataImportReport(
        replaced: true,
        tasCount: 2,
        worldsCount: 1,
        conversationsCount: 3,
        backupPath: '/tmp/b.zip',
      );
      expect(r.replaced, isTrue);
      expect(r.tasCount, 2);
      expect(r.worldsCount, 1);
      expect(r.conversationsCount, 3);
      expect(r.backupPath, '/tmp/b.zip');
      expect(r.backupError, isNull);
    });
  });

  group('TaExportImportService.importCharacter（纯解析，无平台依赖）', () {
    test('本应用导出格式可被正确导入', () {
      // 直接构建一个 ExportPackage 再导入，等价于 export → import 往返
      final ExportPackage pkg = ExportPackage(
        version: 1,
        exportType: 'single',
        exportedAt: '2026',
        compressed: false,
        character: ExportedCharacter(
          id: 'ta-import-1',
          name: '导入角色',
          gender: '女',
          persona: 'persona-import',
          intro: 'intro-import',
          opening: 'opening-import',
          tags: <String>['tag-x'],
          dialogueStyle: const <Map<String, String>>[
            <String, String>{'user': 'u', 'assistant': 'a'},
          ],
          images: const <String, ExportedImageInfo>{},
        ),
        protection: <String, dynamic>{'originalLink': 'https://example.com/link'},
      );
      final String jsonString = jsonEncode(pkg.toJson());

      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(jsonString);
      expect(result.success, isTrue);
      final TA ta = result.data!.ta;
      expect(ta.id, 'ta-import-1');
      expect(ta.name, '导入角色');
      expect(ta.persona, 'persona-import');
      expect(ta.tags, <String>['tag-x']);
      expect(ta.dialogueStyle.first.assistant, 'a');
      expect(ta.protection?['originalLink'], 'https://example.com/link');
    });

    test('酒馆 v2 角色卡可被识别并导入', () {
      final String silly = jsonEncode(<String, dynamic>{
        'spec': 'chara_card_v2',
        'data': <String, dynamic>{
          'name': '酒馆角色',
          'description': '酒馆简介',
          'personality': '温柔',
          'scenario': '城堡',
          'first_mes': '你好',
          'mes_example': '{{user}}: 在吗\n{{char}}: 我在的',
          'tags': <String>['silly', 'v2'],
        },
      });
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(silly);
      expect(result.success, isTrue);
      final TA ta = result.data!.ta;
      expect(ta.name, '酒馆角色');
      expect(ta.persona, '酒馆简介');
      expect(ta.intro, contains('温柔'));
      expect(ta.intro, contains('城堡'));
      expect(ta.opening, '你好');
      expect(ta.tags, <String>['silly', 'v2']);
      expect(ta.dialogueStyle, hasLength(1));
      expect(ta.dialogueStyle.first.user, '在吗');
      expect(ta.dialogueStyle.first.assistant, '我在的');
    });

    test('酒馆 v1 扁平角色卡可被导入', () {
      final String silly = jsonEncode(<String, dynamic>{
        'name': 'v1角色',
        'description': 'desc v1',
        'first_mes': 'start',
      });
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(silly);
      expect(result.success, isTrue);
      expect(result.data!.ta.name, 'v1角色');
    });

    test('不支持的格式返回失败', () {
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(jsonEncode(<String, dynamic>{
        'foo': 'bar',
      }));
      expect(result.success, isFalse);
      expect(result.message, contains('不支持'));
    });

    test('非 JSON 内容返回失败', () {
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter('not-json{');
      expect(result.success, isFalse);
    });

    test('版本过高返回失败', () {
      final String tooNew = jsonEncode(<String, dynamic>{
        'version': 999,
        'exportType': 'single',
        'character': <String, dynamic>{'id': 'x', 'name': 'n'},
      });
      final ExportImportResult<ImportResult> result =
          TaExportImportService.importCharacter(tooNew);
      expect(result.success, isFalse);
      expect(result.message, contains('版本'));
    });
  });

  group('重构兼容性：模型类可从原 service 文件再导出访问', () {
    test('DataBackupService 暴露 DataBackupManifest / ParsedBackup / DataImportReport', () {
      // 通过实际引用确认 re-export 仍可用（编译期检查）
      const DataBackupManifest m = DataBackupManifest(
        version: 1,
        exportedAt: 't',
        app: 'a',
      );
      expect(m.app, 'a');
    });

    test('TaExportImportService 暴露 ExportPackage / ExportedCharacter / ImportResult', () {
      const ExportPackage pkg = ExportPackage(
        version: 1,
        exportType: 'single',
        exportedAt: 't',
        compressed: false,
        character: ExportedCharacter(
          id: 'c',
          name: 'n',
          gender: '女',
          persona: '',
          intro: '',
          opening: '',
          tags: <String>[],
          dialogueStyle: <Map<String, String>>[],
          images: <String, ExportedImageInfo>{},
        ),
      );
      expect(pkg.character.name, 'n');
    });
  });
}
