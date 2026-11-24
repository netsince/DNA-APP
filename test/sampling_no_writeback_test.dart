import 'package:dna/models/conversation.dart';
import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHive extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}

/// 全局采样参数不能被「编辑模型卡」覆盖。
///
/// 这条测试锁的是审计 F-4 的最坏链条：
/// 用户把全局温度设成 0.5 → 打开某个开了「自定义采样」的模型卡保存 →
/// `_syncActiveModelToLegacyFields` 把模型值写回 `_settings.temperature` →
/// 之后**所有不开自定义采样的模型**都拿到被覆盖后的值，且没有任何提示。
///
/// 请求侧的合并规则本身是对的（`buildLlmRequest` 按「模型覆盖全局」解析），
/// 所以修复只要求：**别把派生值写回用户设置**，请求仍然用模型的自定义值。
void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  test('编辑模型卡不覆盖全局采样参数，但请求仍用模型自定义值', () async {
    final AppController c = await boot();

    await c.patchSettings('temperature', 0.5);
    expect(c.settings.temperature, 0.5, reason: '前置：用户把全局温度设成 0.5');

    final LlmModelConfig model = c.activeModel.copyWith(
      customSamplingEnabled: true,
      temperature: 0.9,
    );
    await c.saveModelConfig(model);

    expect(
      c.settings.temperature,
      0.5,
      reason: '保存模型卡不该把模型的自定义温度写回全局设置',
    );
    expect(
      c.buildLlmRequest(messages: <Map<String, dynamic>>[]).temperature,
      0.9,
      reason: '请求侧仍应按「模型覆盖全局」解析成 0.9',
    );
  });

  test('关掉自定义采样的模型使用用户全局值', () async {
    final AppController c = await boot();
    await c.patchSettings('temperature', 0.5);

    final LlmModelConfig model = c.activeModel.copyWith(
      customSamplingEnabled: false,
      temperature: 0.9,
    );
    await c.saveModelConfig(model);

    expect(c.settings.temperature, 0.5);
    expect(
      c.buildLlmRequest(messages: <Map<String, dynamic>>[]).temperature,
      0.5,
      reason: '未开自定义采样时请求应使用全局值',
    );
  });
}
