import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dna/services/model_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模型能力快照的契约：内容可信、归一化与脚本一致、缺失时退化不崩。
void main() {
  group('模型 id 归一化', () {
    test('去 provider 前缀并小写', () {
      expect(normalizeModelId('OpenAI/GPT-4o'), 'gpt-4o');
      expect(stripProvider('openai/gpt-4o'), 'gpt-4o');
      expect(stripProvider('gpt-4o'), 'gpt-4o');
    });

    test('去日期后缀（两种常见写法）', () {
      expect(normalizeModelId('gpt-4o-2024-11-20'), 'gpt-4o');
      expect(normalizeModelId('claude-3-5-sonnet-20241022'), 'claude-3-5-sonnet');
    });

    test('去 -latest / -preview / -stable', () {
      expect(normalizeModelId('gpt-4o-latest'), 'gpt-4o');
      expect(normalizeModelId('gemini-2.0-flash-preview'), 'gemini-2.0-flash');
    });

    test('不该被误伤：普通短横线 key 保持原样', () {
      expect(normalizeModelId('qwen2.5-vl-72b'), 'qwen2.5-vl-72b');
      expect(normalizeModelId('glm-4.5v'), 'glm-4.5v');
    });

    test('空串不炸', () {
      expect(normalizeModelId(''), '');
      expect(stripProvider(''), '');
    });
  });

  group('查表', () {
    final ModelCapability vision = const ModelCapability(
      image: true,
      audio: false,
      video: false,
      pdf: true,
      contextWindow: 128000,
      toolCall: true,
      reasoning: false,
      fromSnapshot: true,
    );

    setUp(() {
      ModelCapabilities.instance.debugLoadFrom(<String, ModelCapability>{
        'gpt-4o': vision,
        'openai/gpt-4o': vision,
      });
    });

    test('精确命中', () {
      expect(ModelCapabilities.instance.lookup('gpt-4o')?.image, isTrue);
    });

    test('带 provider 前缀、带日期后缀都能命中', () {
      expect(ModelCapabilities.instance.lookup('openai/gpt-4o')?.image, isTrue);
      expect(ModelCapabilities.instance.lookup('GPT-4o-2024-11-20')?.image, isTrue);
    });

    test('查不到时 resolve 退化成启发式（不返回 null）', () {
      final ModelCapability cap = ModelCapabilities.instance.resolve('qwen2.5-vl-72b');
      expect(cap.image, isTrue);
      expect(cap.fromSnapshot, isFalse, reason: '不是快照来的就要标出来');
    });

    test('纯文本模型不会被启发式误判成能收图', () {
      expect(ModelCapabilities.instance.resolve('deepseek-chat').image, isFalse);
      expect(ModelCapabilities.instance.resolve('glm-4-flash').image, isFalse);
    });

    test('未加载任何表时 lookup 返回 null 而不抛错', () {
      ModelCapabilities.instance.debugLoadFrom(null);
      expect(ModelCapabilities.instance.lookup('gpt-4o'), isNull);
    });
  });

  group('工程内的快照文件', () {
    test('存在、可解压、数量与关键模型正确', () {
      final File f = File('assets/data/model_capabilities.json.gz');
      expect(f.existsSync(), isTrue, reason: '快照应由 tools/update_model_capabilities.mjs 生成');
      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(GZipDecoder().decodeBytes(f.readAsBytesSync())),
      ) as Map<String, dynamic>;
      expect(json['v'], 1);
      expect(json['fields'], isA<List<dynamic>>());
      expect((json['modelCount'] as int) > 1000, isTrue);
      final Map<String, dynamic> models = json['models'] as Map<String, dynamic>;

      List<int> caps(String id) => (models[id] as List<dynamic>).cast<int>();

      expect(caps('gpt-4o')[0], 1, reason: 'gpt-4o 应该能吃图');
      expect(caps('gpt-4o')[4], greaterThan(0), reason: '上下文窗口不该是 0');
      expect(caps('deepseek-chat')[0], 0, reason: 'deepseek-chat 是纯文本');
    });
  });
}
