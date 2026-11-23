import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/prompt_strategy.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/conversation_export_import_service.dart';
import 'package:dna/widgets/glass_quality.dart';

/// 持久化标识符的守卫。
///
/// 对应 `docs/LOCALIZATION_IDENTITY_AUDIT.md` 的 A2 / A3 / B：
/// * A2：错误**种类**不能靠比较错误**文案**来判断；
/// * A3：给人读的导出文稿可以有兜底文案，结构化 JSON 里不许有；
/// * B ：用「代码标识符」当持久化键的地方，改名不能悄悄发生。
///
/// 这些断言都能失败：改一个枚举成员名、把兜底文案塞进 JSON、用文案做判断，
/// 对应测试立刻红。
void main() {
  group('B · 持久化键冻结（改名即红）', () {
    // 清单是现场从源码里枚举出来的，不是手抄。
    const Map<String, List<String>> frozen = <String, List<String>>{
      'AdvanceStrategy': <String>['forced', 'free'],
      'ImmersionStrategy': <String>['restrained', 'strong'],
      'LengthStrategy': <String>['strict', 'medium', 'unlimited', 'custom'],
      'IntensityLevel': <String>[
        'unrestricted',
        'mild',
        'moderate',
        'marked',
        'strong',
        'extreme',
      ],
      'Pov': <String>['first', 'third', 'omniscient'],
      'NarrativeStructure': <String>[
        'threeAct',
        'chapters',
        'slice',
        'loop',
        'epistolary',
      ],
      'Pacing': <String>['scene', 'chronological', 'fragmented'],
      'TensionCurve': <String>['rising', 'wave', 'flat', 'spike'],
      'Reveal': <String>['layered', 'all', 'blank', 'unreliable', 'limited'],
      'ConflictSource': <String>[
        'interpersonal',
        'inner',
        'environment',
        'institution',
        'supernatural',
      ],
      'EndingStyle': <String>['open', 'closed', 'loop'],
      'AddressMode': <String>['fixed', 'relationship', 'emotion', 'custom'],
      'EmotionTone': <String>[
        'calm',
        'warm',
        'danger',
        'humor',
        'suspense',
        'sweet',
      ],
    };

    test('PromptStrategy 各枚举的成员名与冻结清单一致', () {
      final Map<String, List<String>> actual = <String, List<String>>{
        'AdvanceStrategy': AdvanceStrategy.values
            .map((AdvanceStrategy e) => e.name)
            .toList(),
        'ImmersionStrategy': ImmersionStrategy.values
            .map((ImmersionStrategy e) => e.name)
            .toList(),
        'LengthStrategy': LengthStrategy.values
            .map((LengthStrategy e) => e.name)
            .toList(),
        'IntensityLevel': IntensityLevel.values
            .map((IntensityLevel e) => e.name)
            .toList(),
        'Pov': Pov.values.map((Pov e) => e.name).toList(),
        'NarrativeStructure': NarrativeStructure.values
            .map((NarrativeStructure e) => e.name)
            .toList(),
        'Pacing': Pacing.values.map((Pacing e) => e.name).toList(),
        'TensionCurve': TensionCurve.values
            .map((TensionCurve e) => e.name)
            .toList(),
        'Reveal': Reveal.values.map((Reveal e) => e.name).toList(),
        'ConflictSource': ConflictSource.values
            .map((ConflictSource e) => e.name)
            .toList(),
        'EndingStyle': EndingStyle.values.map((EndingStyle e) => e.name).toList(),
        'AddressMode': AddressMode.values.map((AddressMode e) => e.name).toList(),
        'EmotionTone': EmotionTone.values.map((EmotionTone e) => e.name).toList(),
      };

      for (final MapEntry<String, List<String>> e in frozen.entries) {
        expect(
          actual[e.key],
          e.value,
          reason:
              '${e.key} 的成员名变了 —— 这个词同时是老存档里的持久化值，'
              '改名等于让老用户的设置静默回落到默认。要么改回去，要么加迁移。',
        );
      }
    });

    test('GlassQuality 用显式 key 落盘，不用枚举标识符', () {
      expect(
        GlassQuality.values.map((GlassQuality q) => q.key).toList(),
        <String>['high', 'medium', 'off'],
      );
      // 历史版本存的就是标识符，与 key 同值，老存档能原样读回来。
      expect(GlassQuality.fromKey('high'), GlassQuality.high);
      expect(GlassQuality.fromKey('medium'), GlassQuality.medium);
      expect(GlassQuality.fromKey('off'), GlassQuality.off);
      expect(GlassQuality.fromKey('不存在的值'), isNull);
      expect(GlassQuality.fromKey(null), isNull);
    });
  });

  group('A2 · 错误种类不用文案判断', () {
    test('惩罚页不再拿错误文案做比较', () {
      // 只看代码行：注释里引用旧写法是正常的（那是解释，不是逻辑）。
      final String code = File('lib/island_app/punishments_page.dart')
          .readAsLinesSync()
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        RegExp(r"_error\s*==\s*'").hasMatch(code),
        isFalse,
        reason: '又出现了「用错误文案做控制流」的写法 —— 改一个字规则就静默失效',
      );
      expect(code.contains('_PunishmentLoadError'), isTrue);
    });
  });

  group('A3 · 文稿可以有兜底，结构里不许有', () {
    Conversation namelessSingle() => const Conversation(
      id: 'c1',
      taId: 'ta-missing',
      worldId: null,
      note: '备注',
      messages: <ConversationMessage>[],
      backgroundMode: 'plain',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[],
      activeTaId: null,
    );

    test('Markdown 文稿用兜底标题（给人读，随语言变是预期）', () async {
      final ConversationExportResult r =
          await ConversationExportImportService.buildConversationExport(
            conversations: <Conversation>[namelessSingle()],
            tasById: const <String, TA>{},
            format: ConversationExportFormat.markdown,
            includeCharacterCards: false,
          );
      expect(
        r.content.contains(
          ConversationExportImportService.fallbackChatTitle,
        ),
        isTrue,
      );
    });

    test('JSON 结构里不注入兜底文案（跨语言导出必须一致）', () async {
      final ConversationExportResult r =
          await ConversationExportImportService.buildConversationExport(
            conversations: <Conversation>[namelessSingle()],
            tasById: const <String, TA>{},
            format: ConversationExportFormat.json,
            includeCharacterCards: false,
          );
      final Map<String, dynamic> envelope =
          jsonDecode(r.content) as Map<String, dynamic>;
      final List<dynamic> list = envelope['conversations'] as List<dynamic>;
      final Map<String, dynamic> first = list.first as Map<String, dynamic>;

      // 名字为空就写空串，不许翻译成「对话」「角色」之类。
      expect(first['groupName'], '');
      for (final String fallback in <String>[
        ConversationExportImportService.fallbackChatTitle,
        ConversationExportImportService.fallbackGroupTitle,
        ConversationExportImportService.fallbackSpeakerName,
      ]) {
        expect(
          r.content.contains(fallback),
          isFalse,
          reason: '结构化导出里出现了兜底文案「$fallback」',
        );
      }
    });
  });
}
