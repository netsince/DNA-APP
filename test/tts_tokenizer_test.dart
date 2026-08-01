import 'package:flutter_test/flutter_test.dart';
import 'package:dna/services/tts/wordpiece_tokenizer.dart';

void main() {
  late WordPieceTokenizer tok;
  setUpAll(() {
    tok = WordPieceTokenizer.fromFile(
      r'D:\duetnurturingally\dna-client\modelwksps\models\tokenizer\tokenizer.json',
    );
  });

  test('特殊 token id 正确', () {
    expect(tok.spkEmbId, 21143);
    expect(tok.break0Id, 21147);
    expect(tok.eosId, 21136);
  });

  test('中文单字编码', () {
    final List<int> ids = tok.encode('你好');
    expect(ids, <int>[872, 1962]);
  });

  test('decorate code prompt + encode', () {
    final String decorated = tok.decorateCodePrompt(
      '你好',
      '',
      hasSpeaker: true,
    );
    expect(decorated, '[Stts][spk_emb]你好[Ptts]');
    final List<int> ids = tok.encode(decorated);
    expect(ids, <int>[21131, 21143, 872, 1962, 21132]);
  });

  test('decorate text prompt', () {
    final String decorated = tok.decorateTextPrompt('你好');
    expect(decorated, '[Sbreak]你好[Pbreak]');
    final List<int> ids = tok.encode(decorated);
    // [Sbreak]=21134, 你=872, 好=1962, [Pbreak]=21135
    expect(ids, <int>[21134, 872, 1962, 21135]);
  });

  test('decode 往返', () {
    final String out = tok.decode(<int>[872, 1962]);
    expect(out, '你好');
  });
}
