import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/services/tts/tts_service.dart';
import 'package:dna/utils/platform_capabilities.dart';
import 'package:dna/widgets/fit_text.dart';

/// 第三方开源组件条目。
class _OssItem {
  const _OssItem({
    required this.name,
    required this.purpose,
    required this.license,
    required this.url,
    this.notice,
  });

  final String name;
  final String purpose;
  final String license;
  final String url;

  /// 需要随分发附带的 Notice / 署名信息（如有）。
  final String? notice;
}

/// 本项目使用的第三方开源项目清单。
const List<_OssItem> _kOssItems = <_OssItem>[
  _OssItem(
    name: 'Flutter',
    purpose: '跨平台 UI 框架（本应用的基础框架）',
    license: 'BSD-3-Clause',
    url: 'https://github.com/flutter/flutter',
  ),
  _OssItem(
    name: 'Dart SDK',
    purpose: '编程语言与运行时',
    license: 'BSD-3-Clause',
    url: 'https://github.com/dart-lang/sdk',
  ),
  _OssItem(
    name: 'cupertino_icons',
    purpose: 'iOS 风格图标',
    license: 'MIT',
    url: 'https://pub.dev/packages/cupertino_icons',
  ),
  _OssItem(
    name: 'http',
    purpose: 'HTTP 网络请求',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/http',
  ),
  _OssItem(
    name: 'image',
    purpose: '图像解码 / 编码与处理',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/image',
  ),
  _OssItem(
    name: 'flutter_image_compress',
    purpose: '图片压缩',
    license: 'MIT',
    url: 'https://pub.dev/packages/flutter_image_compress',
  ),
  _OssItem(
    name: 'image_cropper',
    purpose: '图片裁剪',
    license: 'MIT',
    url: 'https://pub.dev/packages/image_cropper',
  ),
  _OssItem(
    name: 'image_picker',
    purpose: '从相册 / 相机选择图片',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/image_picker',
  ),
  _OssItem(
    name: 'palette_generator',
    purpose: '图片主色调提取',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/palette_generator',
  ),
  _OssItem(
    name: 'path',
    purpose: '跨平台路径处理',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/path',
  ),
  _OssItem(
    name: 'path_provider',
    purpose: '获取各平台目录路径',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/path_provider',
  ),
  _OssItem(
    name: 'shared_preferences',
    purpose: '轻量键值持久化',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/shared_preferences',
  ),
  _OssItem(
    name: 'share_plus',
    purpose: '系统分享面板',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/share_plus',
  ),
  _OssItem(
    name: 'hive',
    purpose: '轻量高性能键值数据库',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/hive',
  ),
  _OssItem(
    name: 'hive_flutter',
    purpose: 'Hive 的 Flutter 集成',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/hive_flutter',
  ),
  _OssItem(
    name: 'local_auth',
    purpose: '本地生物识别认证',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/local_auth',
  ),
  _OssItem(
    name: 'local_auth_android',
    purpose: 'local_auth 的 Android 实现',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/local_auth_android',
  ),
  _OssItem(
    name: 'local_auth_ios',
    purpose: 'local_auth 的 iOS 实现',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/local_auth_ios',
  ),
  _OssItem(
    name: 'url_launcher',
    purpose: '打开外部链接',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/url_launcher',
  ),
  _OssItem(
    name: 'uuid',
    purpose: '生成唯一标识符',
    license: 'MIT',
    url: 'https://pub.dev/packages/uuid',
  ),
  _OssItem(
    name: 'tiktoken',
    purpose: 'BPE 分词（OpenAI Tokenizer）',
    license: 'MIT',
    url: 'https://pub.dev/packages/tiktoken',
  ),
  _OssItem(
    name: 'dynamic_color',
    purpose: '动态取色（Material You）',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/dynamic_color',
  ),
  _OssItem(
    name: 'flutter_colorpicker',
    purpose: '颜色选择器',
    license: 'MIT',
    url: 'https://pub.dev/packages/flutter_colorpicker',
  ),
  _OssItem(
    name: 'archive',
    purpose: 'ZIP 压缩 / 解压',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/archive',
  ),
  _OssItem(
    name: 'file_picker',
    purpose: '文件选择',
    license: 'MIT',
    url: 'https://pub.dev/packages/file_picker',
  ),
  _OssItem(
    name: 'sherpa_onnx',
    purpose: '端侧语音识别 / 合成（基于 sherpa-onnx）',
    license: 'Apache-2.0',
    url: 'https://pub.dev/packages/sherpa_onnx',
    notice: 'sherpa-onnx 使用 Apache-2.0 许可证，并可能包含第三方语音模型（各模型按其各自许可证使用）。',
  ),
  _OssItem(
    name: 'onnxruntime',
    purpose: 'ONNX 模型推理（TTS 合成）',
    license: 'MIT',
    url: 'https://pub.dev/packages/onnxruntime',
    notice: 'onnxruntime 的 Flutter 绑定使用 MIT 许可证；底层 ONNX Runtime 使用 MIT 许可证。',
  ),
  _OssItem(
    name: 'ffi',
    purpose: '本地 C/C++ 函数调用',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/ffi',
  ),
  _OssItem(
    name: 'audioplayers',
    purpose: '音频播放',
    license: 'MIT',
    url: 'https://pub.dev/packages/audioplayers',
  ),
  _OssItem(
    name: 'crypto',
    purpose: '哈希与加密',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/crypto',
  ),
  _OssItem(
    name: 'record',
    purpose: '音频录音',
    license: 'MIT',
    url: 'https://pub.dev/packages/record',
  ),
  _OssItem(
    name: 'flutter_lints',
    purpose: '静态分析规则集（开发依赖）',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/flutter_lints',
  ),
  _OssItem(
    name: 'flutter_launcher_icons',
    purpose: '应用图标生成工具（开发依赖）',
    license: 'MIT',
    url: 'https://pub.dev/packages/flutter_launcher_icons',
  ),
  _OssItem(
    name: 'package_info_plus',
    purpose: '读取应用版本号等打包信息',
    license: 'BSD-3-Clause',
    url: 'https://pub.dev/packages/package_info_plus',
  ),
];

/// ChatTTS 语音模型：非随应用打包，而是用户安装 App 后手动下载的模型组件。
/// 因此单独列出——已安装时正常显示；未安装时置灰并置于列表最底部。
const _OssItem _kChatTts = _OssItem(
  name: 'ChatTTS',
  purpose: '端侧语音合成模型（TTS 引擎的声学模型）',
  license: 'AGPL-3.0',
  url: 'https://github.com/2noise/ChatTTS',
  notice: 'ChatTTS 模型基于 AGPL-3.0 许可证发布，请在使用与分发时遵守其许可证要求。',
);

/// 开源页面：列出本项目使用的第三方开源项目、License 与 Notice。
class OpenSourcePage extends StatefulWidget {
  const OpenSourcePage({super.key});

  @override
  State<OpenSourcePage> createState() => _OpenSourcePageState();
}

class _OpenSourcePageState extends State<OpenSourcePage> {
  /// ChatTTS 模型是否已安装。null 表示尚未检测完成。
  bool? _chatTtsReady;

  @override
  void initState() {
    super.initState();
    _checkChatTts();
  }

  Future<void> _checkChatTts() async {
    // Web 端不支持端侧 TTS，直接标记未安装（置灰），不触发原生检测。
    if (!PlatformCapabilities.ttsSupported) {
      if (mounted) setState(() => _chatTtsReady = false);
      return;
    }
    final bool ready = await TtsService.instance.isModelsReady();
    if (!mounted) return;
    setState(() => _chatTtsReady = ready);
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('无法打开链接：$url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('开源组件')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                children: <Widget>[
                  FitText(
                    '本应用基于以下开源项目构建。我们由衷感谢所有开源社区贡献者的工作。'
                    '每个组件的完整许可证文本请访问其对应仓库查看。',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.menu_book_outlined, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FitText(
                              '共 ${_kOssItems.length + 1} 个第三方组件',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 固定开源组件
                  for (final item in _kOssItems) ...[
                    _OssTile(item: item, onTap: () => _open(context, item.url)),
                    const Divider(height: 1),
                  ],
                  // ChatTTS 模型：已安装正常显示；未安装置灰（不可点）并排在末尾。
                  _OssTile(
                    item: _kChatTts,
                    enabled: _chatTtsReady ?? false,
                    trailing: _chatTtsReady == null
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: (_chatTtsReady ?? false)
                        ? () => _open(context, _kChatTts.url)
                        : null,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OssTile extends StatelessWidget {
  const _OssTile({
    required this.item,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final _OssItem item;
  final VoidCallback? onTap;
  final bool enabled;

  /// 自定义尾部组件；默认显示「打开」图标。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FitText(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: enabled ? null : cs.outline,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: enabled ? cs.secondaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FitText(
                          item.license,
                          style: TextStyle(
                            fontSize: 11,
                            color: enabled ? cs.onSecondaryContainer : cs.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  FitText(
                    item.purpose,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: enabled ? cs.onSurfaceVariant : cs.outline),
                  ),
                  if (!enabled) ...[
                    const SizedBox(height: 4),
                    FitText(
                      '未安装 · 需在语音合成设置中下载模型',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.outline),
                    ),
                  ],
                  if (item.notice != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FitText(
                        'Notice: ${item.notice}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.open_in_new, size: 18, color: enabled ? cs.primary : cs.outline),
          ],
        ),
      ),
    );
  }
}
