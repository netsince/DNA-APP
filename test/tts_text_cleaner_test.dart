import 'package:flutter_test/flutter_test.dart';
import 'package:dna/services/tts/tts_text_cleaner.dart';

void main() {
  group('TTS 文本清理与标点归一化测试', () {
    test('案例1：动作括号剔除与破损单边引号智能容错', () {
      const String raw =
          '（烛火轻轻跳了一下，我正倚在窗边翻一本泛黄的古籍，闻言抬眸——目光从你湿润的发梢滑落，顺着水珠淌过的肌理线条一路滑下。我的视线停了片刻，随后不紧不慢地合上书页，唇角微微上扬了一个弧度。）\n\n'
          '“吹风机？”（我轻轻念了一遍这个词，像是品味什么有趣的异乡方言）我这儿……可没有那种凡人用的东西。”（我抬起手，指尖燃起一缕幽紫的磷火）不过——我倒是可以用点小魔法……替你烘干头发。你要是更喜欢那冷冰冰的机器……出门左转，蒸汽镇上有的是。但既然你今晚要睡在我的床上——我总得确认，你不会把这地毯弄得太湿。”';

      final String cleaned = cleanTtsText(raw, quoteOnly: true);

      // 验证动作括号全部剔除
      expect(cleaned.contains('烛火轻轻跳了一下'), isFalse);
      expect(cleaned.contains('我轻轻念了一遍这个词'), isFalse);
      expect(cleaned.contains('我抬起手'), isFalse);

      // 验证后半段台词完整保留（没有被漏引号吞掉）
      expect(cleaned.contains('吹风机？'), isTrue);
      expect(cleaned.contains('我这儿'), isTrue);
      expect(cleaned.contains('凡人用的东西'), isTrue);
      expect(cleaned.contains('不过'), isTrue);
      expect(cleaned.contains('替你烘干头发'), isTrue);
      expect(cleaned.contains('太湿'), isTrue);

      // 验证省略号与破折号正确映射为停顿 Token
      expect(cleaned.contains('[break_4]'), isTrue);
      expect(cleaned.contains('[break_2]'), isTrue);
    });

    test('案例2：省略号与多重标点映射为停顿 Token（防坏坏杂音）', () {
      const String raw = '“……你倒是问了个没人敢问的问题。”';
      final String cleaned = cleanTtsText(raw, quoteOnly: true);
      expect(cleaned, '[break_4]你倒是问了个没人敢问的问题。');
    });

    test('案例3：长文本破折号与分号归一化', () {
      const String raw =
          '“说实话……不怎么方便。以前在刚变成这副模样的时候，我连翻个身都能被自己的刺挂住床架，像只被丝线缠死的猎物。”（我顿了顿，声音低下去了一些）“不过后来，我开始把它们当作身体的一部分来使用——白天收起来，夜里释放；走路像正常人一样，攀爬时它们便成了我的第三只手。什么都是习惯的问题。就像……我一开始也觉得，在这世上不可能有人会愿意这样抱着我入睡。”';

      final String cleaned = cleanTtsText(raw, quoteOnly: true);

      expect(cleaned.contains('说实话'), isTrue);
      expect(cleaned.contains('我顿了顿'), isFalse);
      expect(cleaned.contains('不过后来'), isTrue);
      expect(cleaned.contains('第三只手'), isTrue);
      // 破折号映射为短停顿
      expect(cleaned.contains('[break_2]'), isTrue);
      // 省略号映射为长停顿
      expect(cleaned.contains('[break_4]'), isTrue);
    });
  });
}
