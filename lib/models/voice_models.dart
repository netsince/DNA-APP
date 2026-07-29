/// 可切换的离线语音识别（sherpa-onnx 流式 ASR）模型选项。
///
/// 模型均为 transducer（zipformer）流式架构，下载后由 [SpeechToTextService]
/// 在目录中自动定位 encoder/decoder/joiner/tokens 文件，因此无需硬编码内部文件名。
/// 模型文件托管于 ModelScope / GitHub（见 [kPresetSherpaSources]），
/// 每个 [VoiceModelOption.fileName] 对应仓库中的 `<name>.tar.bz2`。
///
/// 注意：文件名必须与 ModelScope 仓库
/// `zhaochaoqun/sherpa-onnx-asr-models` 的 master 分支实际文件完全一致，
/// 且同名文件在 GitHub Releases 的 `asr-models` 中也存在（两边共用同一 fileName）。
class VoiceModelOption {
  const VoiceModelOption({
    required this.id,
    required this.label,
    required this.description,
    required this.fileName,
    required this.languages,
  });

  /// 唯一 id，同时作为本地解压目录名。
  final String id;

  /// 展示名称。
  final String label;

  /// 简短说明（语言 / 体积 / 适用场景）。
  final String description;

  /// 模型压缩包文件名（不含路径）。
  final String fileName;

  /// 支持的语言标签。
  final String languages;
}

/// 默认模型 id（中英双语流式模型，体积约 511MB，适合中文用户）。
const String kVoiceModelDefaultId =
    'sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20';

/// 可选模型列表。可在此自由增删，界面会据此渲染下拉选项。
///
/// 仅列出仓库中真实存在的「流式（streaming）」模型，以确保 [SpeechToTextService]
/// 的 OnlineRecognizer 可正常加载。
const List<VoiceModelOption> kVoiceModelOptions = <VoiceModelOption>[
  VoiceModelOption(
    id: 'sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20',
    label: '中英双语（标准）',
    description: '中英双语，体积约 511MB，识别最稳，推荐。',
    fileName:
        'sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2',
    languages: '中文 / 英文',
  ),
  VoiceModelOption(
    id: 'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23',
    label: '中文超轻量（14M）',
    description: '仅中文，模型约 74MB，极省资源。',
    fileName:
        'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
    languages: '中文',
  ),
  VoiceModelOption(
    id: 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17',
    label: '英文轻量（20M）',
    description: '仅英文，模型约 128MB，轻量移动端。',
    fileName:
        'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2',
    languages: '英文',
  ),
  VoiceModelOption(
    id: 'sherpa-onnx-streaming-paraformer-bilingual-zh-en',
    label: '中英双语（Paraformer）',
    description: '中英双语，约 226MB，Paraformer 架构。',
    fileName:
        'sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2',
    languages: '中文 / 英文',
  ),
];

/// 按 id 查找模型选项，找不到时返回默认模型。
VoiceModelOption voiceModelById(String id) {
  for (final VoiceModelOption m in kVoiceModelOptions) {
    if (m.id == id) {
      return m;
    }
  }
  return kVoiceModelOptions.first;
}
