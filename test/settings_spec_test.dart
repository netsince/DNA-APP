import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';
import 'package:dna/pages/settings/spec/settings_fields_page.dart';
import 'package:dna/pages/settings/spec/settings_spec.dart';
import 'package:dna/pages/settings/spec/settings_tree.dart';

/// 设置声明的规格测试。
///
/// 这一组断言守住的是**配置驱动的不变量**：
///
/// > 任何可写设置都必须在设置树里有一条声明，且声明与
/// > AppSettings.toJson() 的键、类型逐条对得上。
///
/// 每条都能失败 —— 破坏性验证见文件末尾的注释。
void main() {
  // 仓库里的惯例：空 map 走 fromJson 得到一套默认值。
  final AppSettings base = AppSettings.fromJson(const <String, dynamic>{});
  final Map<String, dynamic> defaults = base.toJson();

  final List<SettingValueItem<dynamic>> valueItems = _collectValueItems();
  final List<SettingItemSpec> allItems = _collectAllItems();

  group('声明 ↔ 模型 对账', () {
    test('每个声明的 key 都存在于 AppSettings.toJson()', () {
      final List<String> missing = <String>[
        for (final SettingValueItem<dynamic> item in valueItems)
          if (!defaults.containsKey(item.key)) item.key,
      ];
      expect(missing, isEmpty, reason: '这些 key 在声明里写了，但 toJson 里没有：$missing');
    });

    test('声明类型与 settingsKeyKinds 一致', () {
      for (final SettingValueItem<dynamic> item in valueItems) {
        expect(
          settingsKeyKinds.containsKey(item.key),
          isTrue,
          reason: '${item.id} 的 key ${item.key} 不在 settingsKeyKinds 里',
        );
        expect(
          settingsKeyKinds[item.key],
          _kindOfItem(item),
          reason: '${item.id} 的声明类型与 settingsKeyKinds 不一致',
        );
      }
    });

    test('声明类型与 toJson 的运行时值类型一致', () {
      for (final SettingValueItem<dynamic> item in valueItems) {
        final Object? runtime = defaults[item.key];
        if (runtime == null) continue; // 可空字段的默认值是 null，无法据此判型
        expect(
          _kindOfValue(runtime),
          settingsKeyKinds[item.key],
          reason: '${item.id}: toJson 里 ${item.key} 是 ${runtime.runtimeType}',
        );
      }
    });

    test('同一个 key 不能被两条声明同时使用', () {
      final Map<String, List<String>> byKey = <String, List<String>>{};
      for (final SettingValueItem<dynamic> item in valueItems) {
        byKey.putIfAbsent(item.key, () => <String>[]).add(item.id);
      }
      final Map<String, List<String>> dup = <String, List<String>>{
        for (final MapEntry<String, List<String>> e in byKey.entries)
          if (e.value.length > 1) e.key: e.value,
      };
      expect(dup, isEmpty, reason: '一个字段被两处声明，会互相覆盖：$dup');
    });

    test('反向覆盖：toJson 里每个键都有归属（声明 / 内部 / 动作项 / 自定义页）', () {
      final Set<String> declared = <String>{
        for (final SettingValueItem<dynamic> item in valueItems) item.key,
      };
      final List<String> orphans = <String>[
        for (final String key in defaults.keys)
          if (!declared.contains(key) &&
              !settingsInternalKeys.contains(key) &&
              !settingsActionManagedKeys.contains(key) &&
              !settingsCustomPageKeys.containsKey(key))
            key,
      ];
      expect(
        orphans,
        isEmpty,
        reason:
            '这些键没有归属 —— 新增设置字段时必须同时给它一个界面入口，'
            '或者在「内部状态 / 动作项托管 / 由手写页面管理」里登记并写明理由：'
            '$orphans',
      );
    });

    test('四个桶互不重叠（一个 key 只能有一个归属）', () {
      final Set<String> declared = <String>{
        for (final SettingValueItem<dynamic> item in valueItems) item.key,
      };
      final Map<String, List<String>> buckets = <String, List<String>>{
        '已声明': declared.toList(),
        '内部状态': settingsInternalKeys.toList(),
        '动作项托管': settingsActionManagedKeys.toList(),
        '自定义页': settingsCustomPageKeys.keys.toList(),
      };
      final List<String> overlap = <String>[];
      for (final String key in defaults.keys) {
        final int hits = buckets.values
            .where((List<String> b) => b.contains(key))
            .length;
        if (hits > 1) overlap.add(key);
      }
      expect(
        overlap,
        isEmpty,
        reason: '这些 key 同时出现在多个桶里，豁免会互相掩盖：$overlap',
      );
    });

    test('「由手写页面管理」的每条都必须写明理由', () {
      for (final MapEntry<String, String> e in settingsCustomPageKeys.entries) {
        expect(
          e.value.trim().length,
          greaterThanOrEqualTo(10),
          reason: 'key ${e.key} 的理由太短，等于没写 —— 请说明它属于哪个页面、'
              '为什么那个页面不能声明化',
        );
      }
    });
  });

  group('声明自身自洽', () {
    test('数值项：min < max，default 在范围内，step 合理', () {
      for (final SettingItemSpec item in allItems) {
        if (item is! SettingNumber) continue;
        expect(item.min < item.max, isTrue, reason: '${item.id} 的 min ≥ max');
        expect(
          item.defaultValue >= item.min && item.defaultValue <= item.max,
          isTrue,
          reason:
              '${item.id} 的默认值 ${item.defaultValue} 不在 '
              '[${item.min}, ${item.max}] 内',
        );
        expect(item.step > 0, isTrue, reason: '${item.id} 的 step 必须为正');
      }
    });

    test('枚举项：默认值必须在选项里', () {
      for (final SettingItemSpec item in allItems) {
        if (item is! SettingChoice) continue;
        final List<dynamic> values = item.options
            .map((ChoiceOption<dynamic> o) => o.value)
            .toList();
        expect(
          values.contains(item.defaultValue),
          isTrue,
          reason: '${item.id} 的默认值 ${item.defaultValue} 不在选项 $values 里',
        );
      }
    });

    test('文案长度与 id 唯一', () {
      final Set<String> ids = <String>{};
      for (final SettingItemSpec item in allItems) {
        expect(item.id.trim(), isNotEmpty, reason: '存在空 id');
        expect(ids.add(item.id), isTrue, reason: 'id 重复：${item.id}');
        // 硬线 26 字，12 字是推荐值。
        //
        // 为什么不是 12：采样参数这类字段名本身就带英文术语
        // （「频率惩罚 (Frequency Penalty)」= 24 字），砍成「频率惩罚」会让
        // 熟悉参数的人对不上号。这条断言只用来拦「把一整句话当标题」。
        expect(
          item.title.characters.length <= 26,
          isTrue,
          reason:
              '${item.id} 的标题过长（${item.title.characters.length} 字）：'
              '标题只放名字（推荐 ≤12 字），解释放 hint',
        );
        if (item.subtitle != null) {
          expect(
            item.subtitle!.characters.length <= 24,
            isTrue,
            reason: '${item.id} 的副标题超过 24 字，请把细节移到 hint',
          );
        }
      }
      for (final SettingsEntrySpec entry in settingsTree) {
        expect(
          entry.subtitle.characters.length <= 24,
          isTrue,
          reason: '入口 ${entry.id} 的副标题超过 24 字',
        );
      }
    });
  });

  group('运行态门槛（异步能力探测）', () {
    SettingItemSpec itemById(String id) =>
        allItems.firstWhere((SettingItemSpec i) => i.id == id);

    test('TTS 开关：模型未就绪时置灰，就绪或未探测时可用', () {
      final SettingItemSpec tts = itemById('tts.enabled');
      bool enabledWith(bool? ready) => settingsItemEnabled(
        tts,
        SettingsRuntime(settings: base, ttsModelsReady: ready),
      );

      expect(enabledWith(false), isFalse, reason: '模型没就绪还能点开 = 旧页面的置灰丢了');
      expect(enabledWith(true), isTrue);
      // null = 还没探测完 / 该页面不关心：不能因为「不知道」就先禁用。
      expect(enabledWith(null), isTrue, reason: '探测未完成不应把开关锁死');
    });

    test('TTS 页必须挂运行态钩子（否则上面的置灰永远拿不到状态）', () {
      final FieldsEntry tts = _allFieldEntries().firstWhere(
        (FieldsEntry e) => e.id == 'tts',
      );
      expect(tts.resolveRuntime, isNotNull);
    });


    test('两态副标题：TTS 随模型就绪切换（来源是运行态）', () {
      final SettingItemSpec item = itemById('tts.enabled');
      expect(item.subtitleOf, isNotNull, reason: 'TTS 副标题应该是状态指示');
      final String notReady = item.subtitleOf!(
        SettingsRuntime(settings: base, ttsModelsReady: false),
      );
      final String ready = item.subtitleOf!(
        SettingsRuntime(settings: base, ttsModelsReady: true),
      );
      expect(notReady.trim(), isNotEmpty);
      expect(
        notReady == ready,
        isFalse,
        reason: 'TTS 的两态副标题退化成了一句常量',
      );
    });


    test('行内短说明仍是行内（不能被降级成 subtitle 多占一行）', () {
      for (final String id in <String>[
        'conversationSend.showParenButton',
        'conversationSend.inspirationIncludeSummary',
        'conversationSend.retrySequential',
      ]) {
        final SettingItemSpec item = itemById(id);
        expect(item, isA<SettingToggle>());
        expect(
          (item as SettingToggle).inlineNote,
          isNotNull,
          reason: '$id 的行内说明丢了',
        );
        expect(
          item.subtitle,
          isNull,
          reason: '$id 又用 subtitle 占了一行 —— 旧版是行内的',
        );
      }
    });

    test('Beta 徽标：TTS 页的分组标题右侧仍有标记', () {
      for (final String entryId in <String>['tts']) {
        final FieldsEntry entry = _allFieldEntries().firstWhere(
          (FieldsEntry e) => e.id == entryId,
        );
        final Iterable<Widget?> trailing = entry.sections.map(
          (SettingSectionSpec s) => s.trailing,
        );
        expect(
          trailing.whereType<Widget>().toList(),
          isNotEmpty,
          reason: '$entryId 页的 Beta 徽标丢了',
        );
      }
    });

    test('安全页：生物识别未录入时两个开关隐藏，录入后出现', () {
      final SettingItemSpec appLock = itemById('security.requireAuthForApp');
      final SettingItemSpec archiveLock = itemById(
        'security.requireAuthForArchive',
      );
      final SettingsRuntime without = SettingsRuntime(settings: base);
      final SettingsRuntime with_ = SettingsRuntime(
        settings: base,
        biometricEnrolled: true,
      );

      expect(settingsItemVisible(appLock, without), isFalse);
      expect(settingsItemVisible(archiveLock, without), isFalse);
      expect(settingsItemVisible(appLock, with_), isTrue);
      expect(settingsItemVisible(archiveLock, with_), isTrue);
    });
  });

  group('序列化完备性', () {
    test('toJson → fromJson 往返不丢任何字段', () {
      final Map<String, dynamic> source = defaults;
      final Map<String, dynamic> round = AppSettings.fromJson(source).toJson();
      for (final String key in source.keys) {
        expect(
          round[key],
          source[key],
          reason:
              '$key 在 fromJson 里没被读回来（或读歪了）：'
              '原本 ${source[key]}，回来 ${round[key]}',
        );
      }
    });
  });
}

/// 所有「声明驱动」的字段页：设置主页上的 + 从开发者选项/命令进入的。
///
/// 后者不在树上，但 key 一样归声明层所有 —— 漏掉它们会让「反向覆盖」把
/// 已经声明过的键误判成没人管。
List<FieldsEntry> _allFieldEntries() => <FieldsEntry>[
  for (final SettingsEntrySpec entry in settingsTree)
    if (entry is FieldsEntry) entry,
  ...settingsDetachedEntries,
];

/// 收集所有**带 key** 的声明。
List<SettingValueItem<dynamic>> _collectValueItems() {
  final List<SettingValueItem<dynamic>> out = <SettingValueItem<dynamic>>[];
  for (final FieldsEntry entry in _allFieldEntries()) {
    for (final SettingSectionSpec section in entry.sections) {
      for (final SettingItemSpec item in section.items) {
        if (item is SettingValueItem) out.add(item);
      }
    }
  }
  return out;
}

/// 收集所有声明（含无 key 的动作项/展示项）。
List<SettingItemSpec> _collectAllItems() {
  final List<SettingItemSpec> out = <SettingItemSpec>[];
  for (final FieldsEntry entry in _allFieldEntries()) {
    for (final SettingSectionSpec section in entry.sections) {
      out.addAll(section.items);
    }
  }
  return out;
}

SettingsValueKind _kindOfItem(SettingValueItem<dynamic> item) {
  if (item is SettingToggle) return SettingsValueKind.boolean;
  if (item is SettingInt) return SettingsValueKind.integer;
  if (item is SettingDouble) return SettingsValueKind.decimal;
  if (item is SettingChoice) {
    return _kindOfValue(item.defaultValue as Object);
  }
  throw StateError('未知的值项类型：${item.runtimeType}');
}

SettingsValueKind _kindOfValue(Object value) {
  if (value is bool) return SettingsValueKind.boolean;
  if (value is int) return SettingsValueKind.integer;
  if (value is double) return SettingsValueKind.decimal;
  if (value is String) return SettingsValueKind.text;
  throw StateError('无法判型的值：${value.runtimeType}');
}

/// **内部状态：永远不进设置界面。**
///
/// 判据：它不是「用户可以选的东西」，而是程序自己的记账（是否完成引导、
/// 模型是否下载好、当前激活的模型 id），或者是编辑器维护的复合对象。
const Set<String> settingsInternalKeys = <String>{
  'completedOobe',
  'chatQuickSidebarCollapsed',
  'activeModelId',
  'promptStrategy',
  'quickReplies',
  'regexRules',
  'providers',
  'models',
  // 没有设置页入口：靠「关于」页连点版本号 10 次切换（见 about_page.dart）。
  'developerOptionsUnlocked',
  // snackDurationMs 曾经在这里：它当时没有界面入口（唯一 setter 已删）。
  // 现在「设置 → 界面与显示 → 提示条停留时长」给了它声明，豁免随之销掉 ——
  // 豁免表不能留着一条已经能改的字段，那会让「孤儿字段」清单失去意义。
};

/// **动作项托管的键：由 SettingAction 里的自绘控件写入，没有标量声明。**
///
/// 判据：声明类型表达不了它的形态 —— 可空整数（清空 = 恢复默认，与 0 语义
/// 不同）、需要 trim 的文本、或带异步探测的取值。它们仍有界面入口（在某个
/// SettingAction 里），只是没法用 `key` 自动读写。
///
/// 每一条都要能说清「为什么不能用标量声明表达」。等声明层补上「可空数值项」
/// 「文本项」之后，这个桶应该缩小到空。
const Set<String> settingsActionManagedKeys = <String>{
  // 可空整数：null = 恢复默认种子的音色，0 是另一个合法取值。
  'ttsGlobalSeed',
  // 可空 ARGB：切回「自动取色」要能真的清空，copyWith 的 ?? 语义表达不了。
  'customAccentColor',
};

/// **由手写页面管理的键：键 → 为什么不能声明化。**
///
/// 这张表是「设置区还有哪些地方不是配置驱动」的**完整清单**，不是垃圾桶：
/// 每条必须指向一个具体的页面与一条具体的理由。新增条目要在评审里被问
/// 「为什么这个页面不能声明化」。
const Map<String, String> settingsCustomPageKeys = <String, String>{
  // —— AI 服务与模型（表单 + 异步探测 + 服务商门控，见 ai_service_settings_page）
  'provider': 'AI 服务页的服务商选择；saveProvider 还会同步 providers 列表，不是单字段写',
  'baseUrl': 'AI 服务页的 Base URL 输入框（表单 + 连接测试 + 服务商锁定地址）',
  'apiKey': 'AI 服务页的 API Key 输入框（密文输入 + 连接测试）',
  'selectedModel': 'AI 服务页的模型选择；选中后要同步写 models 里的默认项',
  'deepseekThinkingEnabled': 'AI 服务页的 DeepSeek 深度思考块：受服务商门控，两个字段一次写',
  'deepseekThinkingEffort': '同上：思考档位与开关属于同一次 saveDeepseekThinking',
  // —— AI 服务页 ⋮ 菜单里的分栏页（3 个 tab：界面模式 / 生成参数 / 网络）
  'simpleModelMode': 'AI 服务 ⋮ → 界面模式 tab 的开关；该页是 3 tab 分栏页，不是字段页',
  'unboundedModelList': '同上：界面模式 tab 的开关',
  'requestTimeoutSeconds': 'AI 服务 ⋮ → 网络 tab 里的超时对话框（与模型列表加载提示耦合）',
  // —— 备份与还原（文件 IO + 平台分支的动作页）
  'autoBackup': '备份与还原页的开关；该页是导出/导入/文件选择 + 平台分支，不是字段页',
  // —— 应用图标选择器（网格 + 平台能力）
  'appIcon': '应用图标选择器的当前项；选择器是网格 + 平台能力判断，不是字段',
};
