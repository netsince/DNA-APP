import 'dart:convert';

import 'package:dna/models/world.dart';
import 'package:dna/services/world_export_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('第三方世界书 JSON 格式导入', () {
    // 常见 worldbook JSON 结构：entries 以 uid 为键。
    final String worldbookJson = jsonEncode(<String, dynamic>{
      'name': '示例世界观',
      'entries': <String, dynamic>{
        'a1b2': <String, dynamic>{
          'uid': 0,
          'key': '精灵, 森林',
          'content': '精灵是森林中的古老种族。',
          'constant': false,
          'disable': false,
          'order': 100,
          'cooldown': 2,
          'delay': 0,
        },
        'c3d4': <String, dynamic>{
          'uid': 1,
          'key': '龙',
          'content': '龙生活在远山。',
          'constant': true,
          'disable': false,
          'order': 50,
        },
        'e5f6': <String, dynamic>{
          'uid': 2,
          'key': '被禁用的词条',
          'content': '不应被导入。',
          'disable': true,
          'order': 0,
        },
      },
    });

    test('importWorld 识别第三方世界书并转换', () {
      final ExportImportResult<World> result =
          WorldExportImportService.importWorld(worldbookJson);
      expect(result.success, isTrue);
      final World world = result.data!;
      expect(world.name, '示例世界观');
      // 禁用的词条被跳过，仅 2 条有效
      expect(world.entries, hasLength(2));
    });

    test('词条字段正确映射', () {
      final ExportImportResult<World> result =
          WorldExportImportService.importWorld(worldbookJson);
      final World world = result.data!;

      final WorldEntry elf = world.entries.firstWhere(
          (WorldEntry en) => en.description.contains('精灵'));
      expect(elf.name, '精灵');
      expect(elf.keys, contains('森林'));
      expect(elf.cooldownRounds, 2);
      expect(elf.order, 100);

      final WorldEntry dragon = world.entries
          .firstWhere((WorldEntry en) => en.name == '龙');
      expect(dragon.decorator, 'activate'); // constant -> activate
      expect(dragon.order, 50);
    });

    test('非世界书结构返回 null', () {
      final World? parsed = WorldExportImportService.parseThirdPartyWorldbook(
        <String, dynamic>{'name': '无 entries'},
      );
      expect(parsed, isNull);
    });
  });
}
