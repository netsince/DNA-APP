import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/ta_export_import_service.dart';

/// 角色卡背景音乐（musicPath）的关键行为测试。
///
/// 覆盖用户明确的设计约束：
/// 1. musicPath 只用于本地持久化与全量备份（TA.toJson/fromJson 携带）；
/// 2. 角色卡导出（exportCharacter）绝不写入 musicPath（防 Base64 撑爆导出包）；
/// 3. 角色卡导入（importCharacter）不识别 musicPath。
void main() {
  TA _baseTa() => TA(
        id: 'ta_1',
        name: '测试角色',
        gender: '女',
        persona: '温柔',
        intro: 'intro',
        opening: '你好',
        tags: const <String>['治愈'],
        images: const <String, String>{'square': '/path/to/img.png'},
        dialogueStyle: const <DialogueTurn>[],
        musicPath: '/doc/tas/music_ta_1.mp3',
      );

  test('TA.toJson / fromJson 往返保留 musicPath（本地持久化/全量备份用）', () {
    final Map<String, dynamic> json = _baseTa().toJson();
    expect(json['musicPath'], '/doc/tas/music_ta_1.mp3');

    final TA restored = TA.fromJson(json);
    expect(restored.musicPath, '/doc/tas/music_ta_1.mp3');
  });

  test('TA.fromJson 缺失 musicPath 时默认为 null（向后兼容）', () {
    final Map<String, dynamic> json = _baseTa().toJson()..remove('musicPath');
    final TA restored = TA.fromJson(json);
    expect(restored.musicPath, isNull);
  });

  test('角色卡导出 exportCharacter 不含 musicPath（防止 Base64 撑爆导出包）', () async {
    final ExportImportResult<String> result =
        await TaExportImportService.exportCharacter(_baseTa());
    expect(result.success, isTrue);

    final Map<String, dynamic> decoded =
        jsonDecode(result.data!) as Map<String, dynamic>;
    // 顶层与 character 内都不应出现 musicPath
    expect(decoded.containsKey('musicPath'), isFalse);
    final Map<String, dynamic> character =
        decoded['character'] as Map<String, dynamic>;
    expect(character.containsKey('musicPath'), isFalse);
  });

  test('角色卡导入 importCharacter 不识别 musicPath（外部卡不携带音乐）', () {
    // 模拟一个「恶意/手写」带 musicPath 的导出包
    final Map<String, dynamic> withMusic = <String, dynamic>{
      'version': 2,
      'exportType': 'single',
      'exportedAt': '2026-01-01T00:00:00.000Z',
      'compressed': false,
      'character': <String, dynamic>{
        'id': 'ta_x',
        'name': '外卡',
        'gender': '无性',
        'persona': '',
        'intro': '',
        'opening': '',
        'tags': <String>[],
        'images': <String, dynamic>{},
        'dialogueStyle': <dynamic>[],
        // 故意塞入 musicPath，验证导入时被忽略
        'musicPath': '/evil/music.mp3',
      },
    };

    final ExportImportResult<ImportResult> result =
        TaExportImportService.importCharacter(jsonEncode(withMusic));
    expect(result.success, isTrue);
    // 导入得到的 TA 不应携带外部塞入的 musicPath
    expect(result.data!.ta.musicPath, isNull);
  });
}
