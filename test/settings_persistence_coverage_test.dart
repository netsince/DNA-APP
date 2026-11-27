import 'package:dna/models/app_settings.dart';
import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置落盘的**结构防线**。
///
/// 背景：存储层改「单表驱动」后，`save()` 只遍历 `kPrefSpecs`。
/// 表里没有的键会被静默跳过——API 配置（apiKey/baseUrl/provider/providers/models…）
/// 就这么漏了，表现为「设置里的 API 存不住」。
///
/// 第一条用例是根防线：**toJson 的每一个键都必须在表里**。
/// 以后每加一个设置字段，它会立刻失败，而不是等用户发现存不住。
void main() {
  test('kPrefSpecs 必须覆盖 AppSettings.toJson() 的每一个键', () {
    final Map<String, dynamic> json = AppSettings.empty().toJson();
    final List<String> missing = json.keys
        .where((String k) => !kPrefSpecs.containsKey(k))
        .toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: '这些键调 save() 时会被静默跳过（永不落盘）：${missing.join(
)}',
    );
  });

  test('API 配置能落盘并读回（回归：曾完全存不住）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService service = SettingsService();

    final AppSettings saved = AppSettings.empty().copyWith(
      baseUrl: 'https://example.com/v1',
      apiKey: 'sk-test-key',
      provider: 'openai',
      selectedModel: 'gpt-test',
      activeModelId: 'm1',
    );
    await service.save(saved);

    final AppSettings loaded = await service.load();
    expect(loaded.baseUrl, 'https://example.com/v1',
        reason: 'baseUrl 必须真的写进 prefs 再读出来');
    expect(loaded.apiKey, 'sk-test-key');
    expect(loaded.provider, 'openai');
    expect(loaded.selectedModel, 'gpt-test');
    expect(loaded.activeModelId, 'm1');
  });

  test('服务商列表与模型列表能往返（复合对象走 object 规格）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService service = SettingsService();

    final AppSettings loaded0 = await service.load();
    final AppSettings saved = loaded0.copyWith(
      providers: <LlmProviderConfig>[
        LlmProviderConfig.defaultConfig(
          providerType: 'openai',
          baseUrl: 'https://a.example/v1',
          apiKey: 'sk-a',
        ),
      ],
      models: <LlmModelConfig>[
        LlmModelConfig.defaultConfig(modelName: 'model-a'),
      ],
    );
    await service.save(saved);

    final AppSettings loaded = await service.load();
    expect(loaded.providers.length, 1);
    expect(loaded.providers.first.apiKey, 'sk-a');
    expect(loaded.providers.first.baseUrl, 'https://a.example/v1');
    expect(loaded.models.first.modelName, 'model-a');
  });

  test('只有旧的扁平键时仍能构造出默认服务商（迁移不回退）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://legacy.example/v1',
      'api_key': 'sk-legacy',
      'selected_model': 'legacy-model',
    });
    final AppSettings loaded = await SettingsService().load();
    expect(loaded.baseUrl, 'https://legacy.example/v1');
    expect(loaded.apiKey, 'sk-legacy');
    expect(loaded.selectedModel, 'legacy-model');
    expect(loaded.providers.first.isDefault, isTrue,
        reason: '默认服务商必须存在，否则设置页读不到可编辑项');
  });
}
