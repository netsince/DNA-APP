import 'package:flutter_test/flutter_test.dart';
import 'package:dna/models/app_settings.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/models/llm_model_config.dart';

void main() {
  group('LlmProviderConfig', () {
    test('default provider ID and alias match specifications', () {
      expect(LlmProviderConfig.defaultId, 'DNAAPP.MODELSETTING.PROVIDER.DEFAULT');
      expect(LlmProviderConfig.defaultAlias, '默认');
    });

    test('toJson and fromJson correctly serialize and deserialize', () {
      final config = LlmProviderConfig(
        id: 'test-id',
        alias: '硅基流动',
        providerType: 'openai',
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiKey: 'sk-test',
      );
      final json = config.toJson();
      final restored = LlmProviderConfig.fromJson(json);
      expect(restored.id, 'test-id');
      expect(restored.alias, '硅基流动');
      expect(restored.providerType, 'openai');
      expect(restored.baseUrl, 'https://api.siliconflow.cn/v1');
      expect(restored.apiKey, 'sk-test');
      expect(restored.isDefault, isFalse);
    });

    test('isDefault returns true for default ID', () {
      final defaultConfig = LlmProviderConfig.defaultConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-default',
      );
      expect(defaultConfig.isDefault, isTrue);
      expect(defaultConfig.id, LlmProviderConfig.defaultId);
      expect(defaultConfig.alias, LlmProviderConfig.defaultAlias);
    });
  });

  group('LlmModelConfig', () {
    test('default model ID and alias match specifications', () {
      expect(LlmModelConfig.defaultId, 'DNAAPP.MODELSETTING.MODEL.DEFAULT');
      expect(LlmModelConfig.defaultAlias, '默认');
    });

    test('toJson and fromJson correctly serialize and deserialize with parameters', () {
      final model = LlmModelConfig(
        id: 'model-1',
        alias: 'DeepSeek-V3 畅聊',
        providerId: 'test-provider-id',
        modelName: 'deepseek-chat',
        customSamplingEnabled: true,
        temperature: 0.8,
        topP: 0.95,
        maxContextTokens: 16000,
        deepseekThinkingEnabled: true,
        deepseekThinkingEffort: 'high',
      );
      final json = model.toJson();
      final restored = LlmModelConfig.fromJson(json);
      expect(restored.id, 'model-1');
      expect(restored.alias, 'DeepSeek-V3 畅聊');
      expect(restored.providerId, 'test-provider-id');
      expect(restored.modelName, 'deepseek-chat');
      expect(restored.customSamplingEnabled, isTrue);
      expect(restored.temperature, 0.8);
      expect(restored.topP, 0.95);
      expect(restored.maxContextTokens, 16000);
      expect(restored.deepseekThinkingEnabled, isTrue);
      expect(restored.deepseekThinkingEffort, 'high');
      expect(restored.isDefault, isFalse);
    });

    test('defaultConfig creates default model matching defaultId and alias', () {
      final defaultModel = LlmModelConfig.defaultConfig(
        modelName: 'gpt-4o',
      );
      expect(defaultModel.isDefault, isTrue);
      expect(defaultModel.id, LlmModelConfig.defaultId);
      expect(defaultModel.alias, LlmModelConfig.defaultAlias);
      expect(defaultModel.providerId, LlmProviderConfig.defaultId);
      expect(defaultModel.modelName, 'gpt-4o');
      expect(defaultModel.customSamplingEnabled, isFalse);
    });
  });

  group('AppSettings migration and multi-model fields', () {
    test('fromJson migrates legacy single provider and model to default items', () {
      final legacyJson = <String, dynamic>{
        'provider': 'anthropic',
        'baseUrl': 'https://api.anthropic.com/v1',
        'apiKey': 'sk-ant-test',
        'selectedModel': 'claude-3-5-sonnet-20241022',
      };
      final settings = AppSettings.fromJson(legacyJson);
      expect(settings.simpleModelMode, isTrue);
      expect(settings.activeModelId, LlmModelConfig.defaultId);
      expect(settings.providers.length, 1);
      expect(settings.providers.first.isDefault, isTrue);
      expect(settings.providers.first.providerType, 'anthropic');
      expect(settings.providers.first.baseUrl, 'https://api.anthropic.com/v1');
      expect(settings.providers.first.apiKey, 'sk-ant-test');
      expect(settings.models.length, 1);
      expect(settings.models.first.isDefault, isTrue);
      expect(settings.models.first.modelName, 'claude-3-5-sonnet-20241022');
    });

    test('toJson and fromJson preserves multi-model lists', () {
      final s = AppSettings.empty().copyWith(
        simpleModelMode: false,
        activeModelId: 'custom-m2',
        providers: [
          LlmProviderConfig.defaultConfig(),
          LlmProviderConfig(
            id: 'p2',
            alias: '智谱',
            providerType: 'zhipu',
            baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
            apiKey: 'key2',
          ),
        ],
        models: [
          LlmModelConfig.defaultConfig(),
          LlmModelConfig(
            id: 'custom-m2',
            alias: 'GLM-4-Flash',
            providerId: 'p2',
            modelName: 'glm-4-flash',
          ),
        ],
      );

      final json = s.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.simpleModelMode, isFalse);
      expect(restored.activeModelId, 'custom-m2');
      expect(restored.providers.length, 2);
      expect(restored.models.length, 2);
      expect(restored.models[1].alias, 'GLM-4-Flash');
    });
  });
}
