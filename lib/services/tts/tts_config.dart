/// ChatTTS ONNX 端侧模型清单与下载配置。
///
/// 模型托管于 ModelScope：https://modelscope.cn/models/aixiaoji/chattts-onnx-int8
/// 每个文件一个独立直链 `resolve/master/<file>`，支持按需/断点下载。
library;

/// 采样率（ChatTTS 固定 24kHz）。
const int kTtsSampleRate = 24000;

/// 本地模型目录名（位于文档目录下）。
const String kTtsModelDirName = 'tts_models';

/// ModelScope 下载根地址（不含末尾斜杠）。
const String kTtsModelBaseUrl =
    'https://modelscope.cn/models/aixiaoji/chattts-onnx-int8/resolve/master';

/// 需下载的模型文件清单。按需下载时按此顺序逐个拉取。
const List<String> kTtsModelFiles = <String>[
  'gpt_emb_quant_int8.onnx',
  'emb_text.onnx',
  'emb_code.onnx',
  'head_text.onnx',
  'head_code.onnx',
  'dvae.onnx',
  'vocos_spectrum.onnx',
  'tokenizer/tokenizer.json',
  'tokenizer/tokenizer_config.json',
  'tokenizer/special_tokens_map.json',
];
