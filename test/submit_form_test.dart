import 'package:dna/widgets/submit_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// 提交式表单收尾器的契约：忙态、失败原因、并发保护。
void main() {
  test('成功：跑完 action，busy 回到 false，无错误', () async {
    final SubmitFormState s = SubmitFormState();
    bool ran = false;
    final bool ok = await s.run(
      action: () async {
        ran = true;
      },
      errorPrefix: '保存失败',
    );
    expect(ok, isTrue);
    expect(ran, isTrue);
    expect(s.busy, isFalse);
    expect(s.errorText, isNull);
  });

  test('失败：原因进 errorText（前缀 + 真实异常），busy 复位', () async {
    final SubmitFormState s = SubmitFormState();
    final bool ok = await s.run(
      action: () async => throw StateError('服务器未配置'),
      errorPrefix: '保存失败',
    );
    expect(ok, isFalse);
    expect(s.busy, isFalse);
    expect(s.errorText, contains('保存失败'));
    expect(s.errorText, contains('服务器未配置'), reason: '不能只给一句"保存失败"');
  });

  test('并发保护：提交中再调用直接返回 false，action 只跑一次', () async {
    final SubmitFormState s = SubmitFormState();
    int runs = 0;
    Future<void> action() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final Future<bool> a = s.run(action: action);
    final Future<bool> b = s.run(action: action);
    expect(await b, isFalse, reason: '忙态时不应再次提交');
    expect(await a, isTrue);
    expect(runs, 1);
  });

  test('clearError 清掉失败原因', () async {
    final SubmitFormState s = SubmitFormState();
    await s.run(action: () async => throw Exception('boom'));
    expect(s.errorText, isNotNull);
    s.clearError();
    expect(s.errorText, isNull);
  });

  test('onFailure 回调拿到原始异常（页面据此聚焦字段等）', () async {
    final SubmitFormState s = SubmitFormState();
    Object? caught;
    await s.run(
      action: () async => throw ArgumentError('bad'),
      onFailure: (Object e) => caught = e,
    );
    expect(caught, isA<ArgumentError>());
  });
}
