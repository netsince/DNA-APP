import 'package:dna/services/stt_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守住语音输入的文本累加：断句提交漏了会导致「松手后一个字都发不出去」，
/// 而且不报错 —— 只靠手测很容易漏。
void main() {
  test('单句：提交后能取到结果', () {
    final SttTranscript t = SttTranscript();
    t.updateCurrent('你好');
    expect(t.display, '你好');
    expect(t.takeFinal(), '你好');
  });

  test('多句：断句累加，最终拼成整段', () {
    final SttTranscript t = SttTranscript();
    t.updateCurrent('第一句');
    t.commitCurrent();
    expect(t.display, '第一句');
    t.updateCurrent('第二句');
    expect(t.display, '第一句第二句');
    expect(t.takeFinal(), '第一句第二句');
  });

  test('提交不会重复累加同一句', () {
    final SttTranscript t = SttTranscript();
    t.updateCurrent('你好');
    t.commitCurrent();
    t.commitCurrent();
    expect(t.takeFinal(), '你好');
  });

  test('只有当前句、没断句时取结果也不为空', () {
    // 这正是真实实现里踩过的坑：只提交了 committed，忘了把当前句并进去。
    final SttTranscript t = SttTranscript();
    t.updateCurrent('半句话');
    expect(t.takeFinal(), '半句话');
  });

  test('取走后复位，下一轮从头开始', () {
    final SttTranscript t = SttTranscript();
    t.updateCurrent('第一轮');
    t.takeFinal();
    expect(t.display, '');
    t.updateCurrent('第二轮');
    expect(t.takeFinal(), '第二轮');
  });

  test('重复的中间结果不重复推送', () {
    final SttTranscript t = SttTranscript();
    expect(t.updateCurrentIfChanged('你好'), isTrue);
    expect(t.updateCurrentIfChanged('你好'), isFalse);
    expect(t.updateCurrentIfChanged('你好呀'), isTrue);
  });
}
