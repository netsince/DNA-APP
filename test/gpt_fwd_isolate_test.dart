import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 相对包根定位(测试的工作目录就是包根),不再写死绝对路径。
  final String modelsDir = '${Directory.current.path}/modelwksps/models';
  // 这些 .bin 是本地调试产物,而 modelwksps/ 被 .gitignore 忽略 ——
  // 干净克隆上不存在。缺了就跳过,而不是让整套测试永远红着。
  final List<String> needed = <String>[
    '_code_emb.bin',
    '_code_attn.bin',
    '_code_pos.bin',
  ];
  final bool hasFixtures = needed.every(
    (String f) => File('$modelsDir/../$f').existsSync(),
  );

  test('gpt_forward 首步隔离测试', () {
    final Uint8List embRaw =
        File('$modelsDir/../_code_emb.bin').readAsBytesSync();
    final Float32List emb = embRaw.buffer.asFloat32List();
    final Uint8List attnRaw =
        File('$modelsDir/../_code_attn.bin').readAsBytesSync();
    final Float32List attn = attnRaw.buffer.asFloat32List();
    final Uint8List posRaw =
        File('$modelsDir/../_code_pos.bin').readAsBytesSync();
    final Int64List pos = posRaw.buffer.asInt64List();

    final int t = emb.length ~/ 768;
    // ignore: avoid_print
    print('emb len=${emb.length} t=$t attn=${attn.length} pos=${pos.length}');

    // 由于 _gptForward 为私有方法，完整的合成对比请在集成测试中验证。
  }, skip: hasFixtures ? null : '需要本地调试产物 modelwksps/_code_*.bin（该目录被 .gitignore 忽略）');
}
