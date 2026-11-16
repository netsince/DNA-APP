import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/ta_gender.dart';

/// TA 性别的「中文当 ID、显示走映射」方案守卫。
///
/// 背景见 `docs/LOCALIZATION_IDENTITY_AUDIT.md` 的 A1：`ta.gender` 的中文值
/// 已经进了存档与社区接口协议，改 ID 要迁数据、还要服务端配合。折中方案是
/// **让中文值直接当稳定 ID**，显示统一走 [TaGender.labelOf]，将来出英文只改
/// label 那一列。
///
/// 这组测试钉住三件事：
/// 1. ID 一个字都不能改（改了存档与服务端就对不上）；
/// 2. 未知值必须原样显示（社区卡来自服务端，可能是任何字符串）；
/// 3. 界面不许再把裸 ID 直接画出来。
void main() {
  group('TaGender：ID 是协议', () {
    test('四个 ID 与历史字面量逐字相同', () {
      expect(TaGender.male.id, '男');
      expect(TaGender.female.id, '女');
      expect(TaGender.agender.id, '无性');
      expect(TaGender.other.id, '其他');
    });

    test('默认值仍是「无性」', () {
      expect(TaGender.fallbackId, '无性');
      expect(TaGender.agender.id, TaGender.fallbackId);
    });

    test('选择器顺序保持历史下拉', () {
      expect(
        TaGender.selectable.map((TaGender g) => g.id).toList(),
        <String>['男', '女', '无性', '其他'],
      );
    });
  });

  group('TaGender：显示映射', () {
    test('已知 ID → 对应文案', () {
      for (final TaGender g in TaGender.selectable) {
        expect(TaGender.labelOf(g.id), g.label);
      }
    });

    test('未知 ID 原样返回，不吞数据', () {
      expect(TaGender.labelOf('外星人'), '外星人');
      expect(TaGender.labelOf('male'), 'male');
    });

    test('null / 空串 → 空串（约定：空表示不显示）', () {
      expect(TaGender.labelOf(null), '');
      expect(TaGender.labelOf(''), '');
    });

    test('byId 精确匹配，不做模糊', () {
      expect(TaGender.byId('男'), TaGender.male);
      expect(TaGender.byId('男性'), isNull);
      expect(TaGender.byId('男 '), isNull);
      expect(TaGender.byId(null), isNull);
    });
  });

  group('界面不许直接画裸 ID（静态守卫）', () {
    String read(String p) => File(p).readAsStringSync();

    test('五个显示点都走 TaGender.labelOf', () {
      for (final String path in <String>[
        'lib/pages/ta_showcase_page.dart',
        'lib/pages/delete_preview_builders.dart',
        'lib/pages/ta_editor/ta_editor_form.dart',
        'lib/island_app/card_detail_page.dart',
        'lib/island_app/widgets/card_tile.dart',
        'lib/island_app/swipe_body.dart',
      ]) {
        expect(
          read(path).contains('TaGender'),
          isTrue,
          reason: '$path 没有走性别映射',
        );
      }
    });

    test('旧的裸用法不再出现', () {
      expect(
        read('lib/pages/delete_preview_builders.dart')
            .contains("_infoRow(cs, tt, '性别', ta.gender)"),
        isFalse,
        reason: '删除确认页又把裸 ID 画出来了',
      );
      expect(
        read('lib/pages/ta_showcase_page.dart')
            .contains("_kv(context, '性别', ta.gender)"),
        isFalse,
        reason: '角色展示页又把裸 ID 画出来了',
      );
      // 2026-11：卡片上的性别标签统一走 StatusBadge（审计 3.3「小标签五套实现」），
      // 私有类 _GenderBadge 已删除；契约不变 —— 送给徽章的是**映射后的 label**。
      // 只看代码行：注释里提到旧类名是正常的（那是解释，不是用法）。
      final String cardTile = read('lib/island_app/widgets/card_tile.dart')
          .split('\n')
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(cardTile.contains('TaGender.labelOf(gender)'), isTrue,
          reason: '社区卡片应把 label 交给 StatusBadge');
      expect(cardTile.contains('_GenderBadge'), isFalse,
          reason: '旧的私有徽章应已收口到 StatusBadge');
    });

    test('编辑页的下拉：value 是 ID、显示是 label', () {
      final String src = read('lib/pages/ta_editor/ta_editor_form.dart');
      expect(src.contains('value: g.id'), isTrue);
      expect(src.contains('child: FitText(g.label)'), isTrue);
      // 历史实现是 value 与 label 都写死中文字面量。
      expect(src.contains("DropdownMenuItem(value: '男'"), isFalse);
    });
  });
}
