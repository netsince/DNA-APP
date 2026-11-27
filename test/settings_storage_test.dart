import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/shared_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置**存储层**的表驱动测试。
///
/// 这组测试是为一个真实缺陷补的：`SettingsService` 的 save/load 曾各自手写
/// 60 多行逐字段赋值，而 `settingsKeyKinds` 声明了 71 个可写键 ——
/// **其中 15 个从来没被存过也没被读过**（高级采样 topP/topK/minP、两个
/// repetition penalty、请求超时、检查更新、Token 面板、允许分叉、命令宏、
/// 正则替换与正则规则、TTS 引号优先、deepseek 思考开关与强度），
/// 用户改完重启就回默认值。
///
/// 现在存/读由 `kPrefSpecs` 一张表驱动，于是可以逐键验证。
void main() {
  final AppSettings base = AppSettings.fromJson(const <String, dynamic>{});

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPrefs.resetForTest();
  });

  test('每个可写键都有存储规格（声明与存储不许再漂移）', () {
    final List<String> missing = <String>[
      for (final String key in settingsKeyKinds.keys)
        if (!kPrefSpecs.containsKey(key)) key,
    ];
    expect(
      missing,
      isEmpty,
      reason: '这些键能被 patch 写入，却没有 pref 存储规格 —— 改了也存不下来: ${missing.join(", ")}',
    );
    // 表里的键分两类：可 patch 的（settingsKeyKinds），以及**只有专门写入入口**的。
    // 后者不能 patch（没有 patch 规则），但必须有存储规格，否则 save() 全量落盘时会
    // 静默跳过 —— API 配置就是这么漏掉的（apiKey/baseUrl/providers/models…）。
    final Set<String> storageOnly = <String>{
      for (final String key in kPrefSpecs.keys)
        if (!settingsKeyKinds.containsKey(key)) key,
    };
    // 允许清单：有专门写入入口、不需要（也不应该）走 patch 的键。
    const Set<String> allowedStorageOnly = <String>{
      'activeModelId',
      'apiKey',
      'baseUrl',
      'models',
      'provider',
      'providers',
      'selectedModel',
    };
    expect(
      storageOnly.difference(allowedStorageOnly),
      isEmpty,
      reason: '表里有既不能 patch、又不在「仅存储」允许清单里的键',
    );
    // 反向：允许清单里的键必须真的在表里（否则它们又会被 save() 跳过）。
    expect(
      allowedStorageOnly.difference(kPrefSpecs.keys.toSet()),
      isEmpty,
      reason: '「仅存储」清单里的键缺失了存储规格，save() 会跳过它们',
    );
  });

  test('逐键往返：save() 之后 load() 能读回同一个值', () async {
    for (final MapEntry<String, SettingsValueKind> entry
        in settingsKeyKinds.entries) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsService service = SettingsService();

      // 复合对象（服务商/模型列表、提示策略、正则规则、快捷回复）没法用
      // 通用方式造「另一个值」——patch 要的是领域对象。这类键只验证
      // 「能存能读回」，标量键才逐个改造后比对。
      final AppSettings patched =
          entry.value == SettingsValueKind.object
          ? base
          : applySettingsPatch(
              base,
              entry.key,
              _perturb(base.toJson()[entry.key], entry.value),
            );
      await service.save(patched);
      final AppSettings loaded = await service.load();

      expect(
        loaded.toJson()[entry.key],
        patched.toJson()[entry.key],
        reason: '${entry.key} 存进去之后读回来不一致',
      );
    }
  });

  test('saveOne 只写一个键，不碰其它键', () async {
    final SettingsService service = SettingsService();
    await service.save(base);

    SharedPreferences prefs = await SharedPrefs.instance;
    final Map<String, Object?> before = <String, Object?>{
      for (final String k in prefs.getKeys()) k: prefs.get(k),
    };

    await service.saveOne('themeMode', 'dark');
    prefs = await SharedPrefs.instance;

    final Set<String> changed = <String>{
      for (final String k in prefs.getKeys())
        if (before[k] != prefs.get(k)) k,
    };
    expect(changed, <String>{'theme_mode'}, reason: '改一个键只能写一个 pref');

    final AppSettings loaded = await service.load();
    expect(loaded.themeMode, 'dark');
  });

  test('saveOne 遇到没有规格的键直接抛错（拼错键不会静默不存）', () async {
    final SettingsService service = SettingsService();
    await expectLater(service.saveOne('notARealKey', true), throwsArgumentError);
  });

  test('置空 = 删键：customAccentColor 清空后不会留 null', () async {
    final SettingsService service = SettingsService();
    await service.save(base.copyWith(customAccentColor: 0xFF123456));
    SharedPreferences prefs = await SharedPrefs.instance;
    expect(prefs.get('custom_accent_color'), 0xFF123456);

    await service.saveOne('customAccentColor', null);
    prefs = await SharedPrefs.instance;
    expect(prefs.get('custom_accent_color'), isNull);
    expect((await service.load()).customAccentColor, isNull);
  });
}

/// 给某个类型造一个「不是默认值」的值，用于往返比对。
Object? _perturb(Object? current, SettingsValueKind kind) {
  switch (kind) {
    case SettingsValueKind.boolean:
      return !((current as bool?) ?? false);
    case SettingsValueKind.integer:
      return ((current as int?) ?? 0) + 7;
    case SettingsValueKind.decimal:
      return ((current as num?) ?? 0).toDouble() + 0.25;
    case SettingsValueKind.text:
      return '${(current ?? '').toString()}x';
    case SettingsValueKind.object:
      // 复合对象没法通用造值：原样回写，只验证「能存能读回」。
      return current;
  }
}
