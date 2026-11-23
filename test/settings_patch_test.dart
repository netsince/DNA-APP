import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';

/// 设置写通道（applySettingsPatch）的行为测试。
///
/// 它要守住两条：
/// 1. 一次 patch 只改一个字段 —— 不能顺手把别的字段带回默认值；
/// 2. 可空字段能被真正清空 —— copyWith 的 `??` 语义做不到，历史上
///    saveCustomAccentColor(null) / saveTtsGlobalSeed(null) 其实是空操作。
void main() {
  final AppSettings base = AppSettings.fromJson(const <String, dynamic>{});
  final Map<String, dynamic> before = base.toJson();

  group('写通道', () {
    test('未声明的 key 直接抛错（拼错键不会静默失败）', () {
      expect(
        () => applySettingsPatch(base, 'notARealKey', true),
        throwsArgumentError,
      );
    });

    test('每个标量键都能写进去，且只改这一个字段', () {
      for (final MapEntry<String, SettingsValueKind> entry
          in settingsKeyKinds.entries) {
        final String key = entry.key;
        if (entry.value == SettingsValueKind.object) continue; // 复合对象不走标量通道
        final Object? current = before[key];
        final Object next = _perturb(current, entry.value);
        final Map<String, dynamic> after = applySettingsPatch(
          base,
          key,
          next,
        ).toJson();
        for (final String other in before.keys) {
          if (other == key) continue;
          expect(after[other], before[other], reason: '写 $key 时顺带改了 $other');
        }
        expect(after[key], isNot(equals(current)), reason: '$key 没被写进去');
      }
    });

    test('在已有改动之上再 patch，不会把先前改动冲掉', () {
      final AppSettings first = applySettingsPatch(base, 'bgmVolume', 80);
      final Map<String, dynamic> jsonAfterFirst = first.toJson();
      expect(jsonAfterFirst['bgmVolume'], 80);

      final AppSettings second = applySettingsPatch(
        first,
        'enterToSend',
        false,
      );
      final Map<String, dynamic> jsonAfterSecond = second.toJson();
      expect(jsonAfterSecond['bgmVolume'], 80, reason: '第二次 patch 冲掉了第一次的改动');
      expect(jsonAfterSecond['enterToSend'], false);
    });

    test('int 键收到 double 时按数值取整，不炸', () {
      final AppSettings s = applySettingsPatch(base, 'bgmVolume', 55.0);
      expect(s.toJson()['bgmVolume'], 55);
    });
  });

  group('可空字段的清空', () {
    test('customAccentColor 能被清空', () {
      final AppSettings withColor = applySettingsPatch(
        base,
        'customAccentColor',
        0xFF123456,
      );
      expect(withColor.toJson()['customAccentColor'], 0xFF123456);

      final AppSettings cleared = applySettingsPatch(
        withColor,
        'customAccentColor',
        null,
      );
      expect(cleared.toJson()['customAccentColor'], isNull);
    });

    test('ttsGlobalSeed 能被清空', () {
      final AppSettings withSeed = applySettingsPatch(
        base,
        'ttsGlobalSeed',
        42,
      );
      expect(withSeed.toJson()['ttsGlobalSeed'], 42);

      final AppSettings cleared = applySettingsPatch(
        withSeed,
        'ttsGlobalSeed',
        null,
      );
      expect(cleared.toJson()['ttsGlobalSeed'], isNull);
    });
  });
}

/// 造一个与当前值不同的同类型值。
Object _perturb(Object? current, SettingsValueKind kind) {
  switch (kind) {
    case SettingsValueKind.boolean:
      return current is bool ? !current : true;
    case SettingsValueKind.integer:
      return current is int ? current + 1 : 1;
    case SettingsValueKind.decimal:
      return current is double ? current + 0.5 : 0.5;
    case SettingsValueKind.text:
      return current is String ? '${current}x' : 'x';
    case SettingsValueKind.object:
      throw StateError('复合对象不应走标量扰动');
  }
}
