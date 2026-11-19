import 'package:dna/widgets/form_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// 编辑器草稿的契约：校验落字段、文本 trim、多选可增删。
void main() {
  test('文本读写与 trim', () {
    final FormDraft d = FormDraft(textFields: <String>['note']);
    d.controller('note').text = '  初遇  ';
    expect(d.rawText('note'), '  初遇  ');
    expect(d.text('note'), '初遇');
    d.dispose();
  });

  test('单选：空串归一成 null，便于「不选择」', () {
    final FormDraft d = FormDraft();
    d.select('world', 'w1');
    expect(d.selection('world'), 'w1');
    d.select('world', '');
    expect(d.selection('world'), isNull);
    d.select('world', null);
    expect(d.selection('world'), isNull);
  });

  test('必填校验：错误落到字段上，不通过返回 false', () {
    final FormDraft d = FormDraft(textFields: <String>['note']);
    final bool ok = d.validateRequired(<(String, String)>[
      ('ta', '请先选择一个 TA。'),
    ]);
    expect(ok, isFalse);
    expect(d.error('ta'), '请先选择一个 TA。');
    expect(d.firstErrorId, 'ta');

    d.select('ta', 'taA');
    expect(d.validateRequired(<(String, String)>[('ta', '请先选择一个 TA。')]), isTrue);
    expect(d.error('ta'), isNull);
    d.dispose();
  });

  test('必填校验把文本字段的空值也算缺失（只有空格不算填了）', () {
    final FormDraft d = FormDraft(textFields: <String>['title']);
    d.controller('title').text = '   ';
    expect(d.validateRequired(<(String, String)>[('title', '请填写标题')]), isFalse);
    d.controller('title').text = '真的写了';
    expect(d.validateRequired(<(String, String)>[('title', '请填写标题')]), isTrue);
    d.dispose();
  });

  test('多选：toggle 增删，setMulti 整体覆盖', () {
    final FormDraft d = FormDraft(multiFields: <String>['members']);
    d.toggleMulti('members', 'a');
    d.toggleMulti('members', 'b');
    expect(d.multiSelection('members'), <String>{'a', 'b'});
    d.toggleMulti('members', 'a');
    expect(d.multiSelection('members'), <String>{'b'});
    d.setMulti('members', <String>['x', 'y']);
    expect(d.multiSelection('members'), <String>{'x', 'y'});
    d.dispose();
  });

  test('未登记的文本字段给出明确错误，而不是静默返回空', () {
    final FormDraft d = FormDraft();
    expect(() => d.controller('nope'), throwsArgumentError);
    d.dispose();
  });
}
