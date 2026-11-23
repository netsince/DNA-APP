import '../models/llm_model_config.dart';
import 'model_capabilities.dart';

/// 解析「当前模型能不能吃图片」，三层优先级：
///
/// 1. 用户在模型设置里显式指定（唯一可靠的判断，支持任意中转/自建服务）；
/// 2. 内置能力快照（models.dev，见 tools/update_model_capabilities.mjs）；
/// 3. 名字启发式（只给个像样的默认值）。
///
/// 任何一层都可能不准 —— 所以这只是「给不给入口」的依据，真正能不能发出去
/// 仍要看请求结果；失败时的回退与记忆在发送侧处理。
bool resolveVisionSupport(LlmModelConfig model) {
  final bool? userSet = model.supportsVision;
  if (userSet != null) return userSet;
  return ModelCapabilities.instance.resolve(model.modelName).image;
}

/// 这个模型的视觉能力来自哪里（给设置页显示「自动判断」的依据）。
String describeVisionSource(LlmModelConfig model) {
  if (model.supportsVision != null) return '已手动指定';
  final ModelCapability cap =
      ModelCapabilities.instance.resolve(model.modelName);
  if (cap.fromSnapshot) {
    return cap.image ? '按模型库识别：支持' : '按模型库识别：不支持';
  }
  return cap.image ? '按模型名推断：可能支持' : '按模型名推断：不支持';
}
