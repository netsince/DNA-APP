import 'package:dna/models/app_settings.dart';
import 'package:dna/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置读取的类型兜底。
///
/// load() 在 runApp 之前执行，一旦抛异常，应用启动后**没有窗口** —— 表现是
/// 「点了没反应」，且日志里只有一行类型错误，极难定位。
///
/// 类型不符是真实存在的：旧版本往同一个键写过 int、手动改过 prefs 文件、
/// 外部工具写过字符串。这些都不该让整个应用起不来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppSettings> loadWith(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    return SettingsService().load();
  }

  test('温度存成整数：读成 1.0 而不是抛错', () async {
    final AppSettings s = await loadWith(<String, Object>{'temperature': 1});
    expect(s.temperature, 1.0);
  });

  test('温度存成字符串：能解析', () async {
    final AppSettings s = await loadWith(<String, Object>{'temperature': '0.35'});
    expect(s.temperature, closeTo(0.35, 1e-9));
  });

  test('整数字段存成小数：四舍五入', () async {
    final AppSettings s =
        await loadWith(<String, Object>{'max_context_messages': 120.6});
    expect(s.maxContextMessages, 121);
  });

  test('整数字段存成字符串：能解析', () async {
    final AppSettings s =
        await loadWith(<String, Object>{'bgm_volume': '30'});
    expect(s.bgmVolume, 30);
  });

  test('完全不相干的类型：退回默认值，不抛错', () async {
    final AppSettings s = await loadWith(<String, Object>{
      'temperature': true,
      'max_context_messages': <String>['oops'],
      'bgm_volume': false,
    });
    expect(s.temperature, 0.7);
    expect(s.maxContextMessages, 120);
    expect(s.bgmVolume, 50);
  });

  test('可空整数字段：脏数据当作未设置', () async {
    final AppSettings s = await loadWith(<String, Object>{
      'custom_accent_color': 'not-a-color',
    });
    expect(s.customAccentColor, isNull);
  });

  test('一堆脏数据混在一起，load 仍能返回完整设置', () async {
    final AppSettings s = await loadWith(<String, Object>{
      'temperature': 2,
      'frequency_penalty': '0.5',
      'presence_penalty': 0.25,
      'snack_duration_ms': 1500.9,
      'lore_budget_tokens': 'bad',
      'chat_mask_strength': 60.2,
    });
    expect(s.temperature, 2.0);
    expect(s.frequencyPenalty, closeTo(0.5, 1e-9));
    expect(s.presencePenalty, closeTo(0.25, 1e-9));
    expect(s.snackDurationMs, 1501);
    expect(s.loreBudgetTokens, 0);
    expect(s.chatMaskStrength, 60);
  });
}
