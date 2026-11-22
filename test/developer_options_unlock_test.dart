import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';
import 'package:dna/pages/settings/developer_options_unlock.dart';
import 'package:dna/pages/settings/spec/settings_spec.dart';
import 'package:dna/pages/settings/spec/settings_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// 开发者选项的「连点版本号解锁」契约。
void main() {
  group('连点计数', () {
    final DateTime t0 = DateTime(2026, 1, 1, 12);

    test('点满 10 次才返回 true', () {
      final DeveloperUnlockCounter c = DeveloperUnlockCounter();
      for (int i = 0; i < 9; i++) {
        expect(c.tap(t0.add(Duration(milliseconds: 100 * i))), isFalse);
      }
      expect(c.tap(t0.add(const Duration(milliseconds: 1000))), isTrue);
    });

    test('点满后清零：再点 10 次会反向切换一次', () {
      final DeveloperUnlockCounter c = DeveloperUnlockCounter();
      for (int i = 0; i < 9; i++) {
        c.tap(t0.add(Duration(milliseconds: 50 * i)));
      }
      expect(c.tap(t0.add(const Duration(milliseconds: 500))), isTrue);
      expect(c.taps, 0, reason: '切换后计数要清零');
      for (int i = 0; i < 9; i++) {
        expect(c.tap(t0.add(Duration(milliseconds: 600 + 50 * i))), isFalse);
      }
      expect(c.tap(t0.add(const Duration(milliseconds: 1200))), isTrue);
    });

    test('间隔超过 3 秒会重新计数', () {
      final DeveloperUnlockCounter c = DeveloperUnlockCounter();
      for (int i = 0; i < 9; i++) {
        c.tap(t0.add(Duration(milliseconds: 100 * i)));
      }
      // 停 5 秒后再点：之前的 9 次作废
      expect(c.tap(t0.add(const Duration(seconds: 6))), isFalse);
      expect(c.taps, 1);
    });

    test('remaining 供提示用', () {
      final DeveloperUnlockCounter c = DeveloperUnlockCounter();
      c.tap(t0);
      expect(c.remaining, 9);
    });
  });

  group('设置值', () {
    test('默认关闭，可写回、可往返 JSON', () {
      expect(AppSettings.empty().developerOptionsUnlocked, isFalse);
      final AppSettings s = applySettingsPatch(
        AppSettings.empty(),
        'developerOptionsUnlocked',
        true,
      );
      expect(s.developerOptionsUnlocked, isTrue);
      expect(
        AppSettings.fromJson(s.toJson()).developerOptionsUnlocked,
        isTrue,
      );
    });

    test('旧存档没有这个字段时按关闭处理', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{}).developerOptionsUnlocked,
        isFalse,
      );
    });
  });

  group('入口显隐', () {
    bool developerVisible(bool unlocked) {
      final SettingsEntrySpec entry =
          settingsTree.firstWhere((SettingsEntrySpec e) => e.id == 'developer');
      final SettingsRuntime runtime = SettingsRuntime(
        settings: AppSettings.empty().copyWith(
          developerOptionsUnlocked: unlocked,
        ),
      );
      return entry.visibleWhen?.call(runtime) ?? true;
    }

    test('未解锁时开发者选项不出现，解锁后出现', () {
      expect(developerVisible(false), isFalse);
      expect(developerVisible(true), isTrue);
    });
  });
}
