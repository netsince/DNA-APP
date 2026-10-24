import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 编辑器「表单 / 外壳」边界守护。
///
/// 表单只负责「字段 + 产出值」。一旦表单里出现 Scaffold/AppBar，就意味着它又开始
/// 自己长外壳 —— 社区壳想改按钮、改标题、加校验时只能传参打补丁，
/// 「按钮写保存、点下去却发布」那类问题就会复发。
void main() {
  const List<String> forms = <String>[
    'lib/pages/world_editor/world_editor_form.dart',
    'lib/pages/ta_editor/ta_editor_form.dart',
    'lib/pages/dialogue_style/dialogue_style_form.dart',
  ];

  const List<String> shells = <String>[
    'lib/pages/world_editor_page.dart',
    'lib/pages/ta_editor_page.dart',
    'lib/pages/dialogue_style_page.dart',
  ];

  for (final String path in forms) {
    test('$path 是表单：不该自带外壳', () {
      final String src = File(path).readAsStringSync();
      expect(src.contains('Scaffold('), isFalse,
          reason: '$path 不该有 Scaffold（外壳负责）');
      expect(src.contains('AppBar('), isFalse,
          reason: '$path 不该有 AppBar（外壳负责）');
      expect(src.contains('floatingActionButton'), isFalse,
          reason: '$path 不该自带 FAB（外壳负责）');
    });
  }

  for (final String path in shells) {
    test('$path 是外壳：必须有 Scaffold 并托管表单', () {
      final String src = File(path).readAsStringSync();
      expect(src.contains('Scaffold('), isTrue,
          reason: '$path 应该由外壳提供 Scaffold');
      expect(
        src.contains('EditorForm(') || src.contains('StyleForm('),
        isTrue,
        reason: '$path 应该托管对应的表单组件');
      expect(src.contains('FormController('), isTrue,
          reason: '$path 应该持有表单句柄');
    });
  }

  test('表单句柄只暴露取值/回填，不暴露存储细节', () {
    for (final String path in <String>[
      'lib/pages/world_editor/world_editor_form.dart',
      'lib/pages/ta_editor/ta_editor_form.dart',
    ]) {
      final String src = File(path).readAsStringSync();
      final int start = src.contains('class WorldFormController')
          ? src.indexOf('class WorldFormController')
          : src.indexOf('class TaFormController');
      expect(start, greaterThan(-1), reason: '$path 里应有表单句柄类');
      final String body = src.substring(start, start + 900);
      expect(body.contains('upsertWorld') || body.contains('upsertTa'),
          isFalse,
          reason: '$path 的句柄不该直接写库（那是外壳的事）');
    }
  });
}
