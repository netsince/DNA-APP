import 'package:flutter_test/flutter_test.dart';

import 'package:dna/pages/chat/chat_models.dart';
import 'package:dna/pages/chat/chat_stream_parser.dart';

/// A2 回归测试:`<think>` 标签被流式分块切成两半时,
/// 不得把半截标签泄漏进可见正文或思考文本。
void main() {
  late Map<String, StreamParseState> states;
  late Map<String, ThoughtEntry> thoughts;
  const String id = 'm1';

  StreamParseState feed(List<String> chunks) {
    StreamParseState state = StreamParseState();
    for (final String chunk in chunks) {
      state = consumeStreamChunk(
        streamStates: states,
        thoughtsByMessageId: thoughts,
        messageId: id,
        chunk: chunk,
      );
    }
    return state;
  }

  setUp(() {
    states = <String, StreamParseState>{};
    thoughts = <String, ThoughtEntry>{};
  });

  group('consumeStreamChunk 基础行为', () {
    test('纯文本直接进入可见正文', () {
      final state = feed(<String>['你好', '呀']);
      expect(state.visible, '你好呀');
      expect(state.thought, '');
    });

    test('完整 think 块在单个 chunk 内', () {
      final state = feed(<String>['<think>内心戏</think>台词']);
      expect(state.visible, '台词');
      expect(state.thought, '内心戏');
    });
  });

  group('A2:标签跨 chunk 撕裂(holdback)', () {
    test('开标签被切断:<thi | nk>', () {
      final state = feed(<String>['前文<thi', 'nk>秘密</think>答案']);
      expect(state.visible, '前文答案',
          reason: '半截 <thi 不得泄漏进可见正文');
      expect(state.thought, '秘密');
    });

    test('闭标签被切断:</thi | nk>', () {
      final state = feed(<String>['<think>abc</thi', 'nk>done']);
      expect(state.visible, 'done', reason: '闭标签之后的内容属于可见正文');
      expect(state.thought, 'abc');
      expect(state.buffer.isEmpty || !state.buffer.contains('</thi'), true);
    });

    test('buffer 恰好等于半个开标签时保持滞留', () {
      final state = feed(<String>['<thi']);
      expect(state.visible, '');
      expect(state.buffer, '<thi');
      // 补上剩余部分后正常解析
      final done = feed(<String>['nk>内容</think>可见']);
      expect(done.visible, '可见');
      expect(done.thought, '内容');
    });

    test('大小写混合的撕裂标签同样处理(findTag 口径为大小写不敏感)', () {
      final state = feed(<String>['text<THIN', 'K>inner</THINK>out']);
      expect(state.visible, 'textout');
      expect(state.thought, 'inner');
    });

    test('以半个标签结尾的流:finalize 把尾巴按字面文本归还', () {
      feed(<String>['回答正文<thi']);
      final String visible = finalizeStreamState(
        streamStates: states,
        thoughtsByMessageId: thoughts,
        messageId: id,
      );
      expect(visible, '回答正文<thi',
          reason: '流已结束,滞留的半截标签就是字面文本,不能丢');
    });

    test('思考未闭合时结束:finalize 归入 thought', () {
      feed(<String>['<think>被截断的思考']);
      final String visible = finalizeStreamState(
        streamStates: states,
        thoughtsByMessageId: thoughts,
        messageId: id,
      );
      expect(visible, '');
      expect(thoughts[id]!.text, '被截断的思考');
    });
  });

  group('stripThoughtTags(完整文本路径)', () {
    test('剥除成对标签', () {
      expect(stripThoughtTags('<think>a</think>b<thought>c</thought>d'), 'bd');
    });

    test('未闭合标签丢弃其后内容(历史行为保持)', () {
      expect(stripThoughtTags('ok<think>hidden'), 'ok');
    });
  });
}
