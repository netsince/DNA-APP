import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/auth_image.dart';

/// 生图相关页面共用的工具与组件。
///
/// 之前 App 的「详情」只有一个全屏图片查看器（标题「生图预览」+ 底部一行提示词），
/// 与网页版 `image_gen/log_detail.html` 差了一大截：没有状态/尺寸/张数/模型/消耗点数/
/// 生成时间，没有参考图，没有复制提示词，没有「同款生成」，失败原因也看不到
/// （而且没有产图的记录连点都点不开）。这里按网页版补齐，改成手机上的竖排布局。

/// 把某一张原图下载到系统临时目录（WebP 原样保存）。
///
/// 详情页与全屏画廊共用：文件名取自提示词，避免两处各写一份导致行为不一致。
Future<void> downloadArtwork(
  BuildContext context, {
  required String url,
  required String prompt,
  int index = 1,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await fetchAuthImageBytes(url);
    final safePrompt = prompt.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
    final trimmed =
        safePrompt.length > 30 ? safePrompt.substring(0, 30) : safePrompt;
    final name = '${trimmed.isEmpty ? 'artwork' : trimmed}_$index.webp';
    final file =
        await File('${Directory.systemTemp.path}${Platform.pathSeparator}$name')
            .writeAsBytes(bytes, flush: true);
    messenger.showSnackBar(SnackBar(content: Text('已下载：${file.path}')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('下载失败，请重试')));
  }
}

/// 状态徽章的文案与配色（与网页版一致：已完成 / 失败 / 生成中）。
({String label, Color bg, Color fg}) _statusBadge(ColorScheme scheme, String st) {
  switch (st) {
    case 'success':
      return (
        label: '已完成',
        bg: scheme.primaryContainer,
        fg: scheme.onPrimaryContainer,
      );
    case 'partial':
      return (
        label: '部分完成',
        bg: scheme.tertiaryContainer,
        fg: scheme.onTertiaryContainer,
      );
    case 'failed':
      return (
        label: '失败',
        bg: scheme.errorContainer,
        fg: scheme.onErrorContainer,
      );
    default:
      return (
        label: st.isEmpty ? '未知' : st,
        bg: scheme.surfaceContainerHighest,
        fg: scheme.onSurfaceVariant,
      );
  }
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw.map((dynamic e) => e.toString()).where((s) => s.isNotEmpty).toList();
}

/// 生图产出的全屏画廊（带认证头加载，左右翻页，可下载当前张）。
///
/// [showPrompt] 为假时不显示底部提示词条 —— 从详情页进来时提示词已经在详情里了。
class ImageGenGalleryPage extends StatefulWidget {
  const ImageGenGalleryPage({
    super.key,
    required this.urls,
    required this.prompt,
    this.initialIndex = 0,
    this.showPrompt = true,
  });

  final List<String> urls;
  final String prompt;
  final int initialIndex;
  final bool showPrompt;

  @override
  State<ImageGenGalleryPage> createState() => _ImageGenGalleryPageState();
}

class _ImageGenGalleryPageState extends State<ImageGenGalleryPage> {
  late final PageController _pageController;
  late int _current;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadCurrent() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    await downloadArtwork(
      context,
      url: widget.urls[_current],
      prompt: widget.prompt,
      index: _current + 1,
    );
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('生图预览', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          if (widget.urls.length > 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${_current + 1}/${widget.urls.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          _downloading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _downloadCurrent,
                  tooltip: '下载原图',
                  icon: const Icon(Icons.download_rounded),
                ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.urls.length,
        onPageChanged: (int i) => setState(() => _current = i),
        itemBuilder: (BuildContext context, int i) {
          return InteractiveViewer(
            child: Center(
              child: Image(
                image: AuthNetworkImage(widget.urls[i]),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: widget.showPrompt
          ? SafeArea(
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.all(kPagePadding),
                child: Text(
                  '提示词：${widget.prompt}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            )
          : null,
    );
  }
}

/// 生图作品详情页（对齐网页版 `image_gen/log_detail.html`，手机竖排布局）。
///
/// 「同款生成」通过 `Navigator.pop(context, prompt)` 把提示词交回工作台。
class ImageGenDetailPage extends StatefulWidget {
  const ImageGenDetailPage({super.key, required this.log});

  final Map<String, dynamic> log;

  @override
  State<ImageGenDetailPage> createState() => _ImageGenDetailPageState();
}

class _ImageGenDetailPageState extends State<ImageGenDetailPage> {
  late final List<String> _images;
  late final List<String> _refs;
  int _current = 0;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _images = _stringList(widget.log['images']);
    _refs = _stringList(widget.log['references']);
  }

  String get _status => (widget.log['status'] ?? '').toString();
  String get _prompt => (widget.log['prompt'] ?? '').toString();
  String get _error => (widget.log['error'] ?? '').toString();
  String get _size => (widget.log['size'] ?? 'auto').toString();
  String get _model => (widget.log['model_name'] ?? '').toString();
  String get _points => (widget.log['points_spent'] ?? '0').toString();
  String get _createdAt => (widget.log['created_at'] ?? '').toString();
  int get _count => (widget.log['count'] as num?)?.toInt() ?? _images.length;
  bool get _failed => _status == 'failed';

  /// 由 `size`（如 1024x1024）推导主图比例；解析失败按 3:4。
  double get _aspect {
    final String s = _size.toLowerCase();
    if (s.contains('x')) {
      final List<String> parts = s.split('x');
      final double? w = double.tryParse(parts[0].trim());
      final double? h = parts.length > 1 ? double.tryParse(parts[1].trim()) : null;
      if (w != null && h != null && h > 0) return w / h;
    }
    return 3 / 4;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (!mounted) return;
    _snack('已复制提示词');
  }

  void _openGallery(List<String> urls, int index) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageGenGalleryPage(
          urls: urls,
          prompt: _prompt,
          initialIndex: index,
          showPrompt: false,
        ),
      ),
    );
  }

  Future<void> _downloadCurrent() async {
    if (_images.isEmpty || _downloading) return;
    setState(() => _downloading = true);
    await downloadArtwork(
      context,
      url: _images[_current],
      prompt: _prompt,
      index: _current + 1,
    );
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ({String label, Color bg, Color fg}) badge = _statusBadge(scheme, _status);
    return Scaffold(
      appBar: AppBar(title: const Text('生图作品详情')),
      body: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: <Widget>[
          _buildStage(scheme),
          if (_images.length > 1) ...<Widget>[
            const SizedBox(height: kListGap),
            _buildThumbs(scheme),
          ],
          const SizedBox(height: kCardGap),
          _buildStatusRow(scheme, badge),
          const SizedBox(height: kCardGap),
          _buildPromptBlock(scheme),
          const SizedBox(height: kListGap),
          _buildMetaChips(scheme),
          if (_refs.isNotEmpty) ...<Widget>[
            const SizedBox(height: kCardGap),
            _buildRefs(scheme),
          ],
          if (_failed && _error.isNotEmpty) ...<Widget>[
            const SizedBox(height: kCardGap),
            _buildError(scheme),
          ],
          const SizedBox(height: kPagePadding),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            kPagePadding,
            kListGap,
            kPagePadding,
            kListGap,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _images.isEmpty || _downloading ? null : _downloadCurrent,
                  icon: _downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('下载原图'),
                ),
              ),
              const SizedBox(width: kListGap),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _prompt.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_prompt),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('同款生成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主图：点击进全屏画廊；失败/无图时给占位说明。
  Widget _buildStage(ColorScheme scheme) {
    if (_images.isEmpty) {
      return AspectRatio(
        aspectRatio: _aspect,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.image_not_supported_outlined,
                    size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: kListGap),
                Text('本次未产出图像',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _openGallery(_images, _current),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: AspectRatio(
          aspectRatio: _aspect,
          child: Image(
            image: AuthNetworkImage(_images[_current]),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(child: Text('图片加载失败')),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbs(ColorScheme scheme) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, _) => const SizedBox(width: kListGap),
        itemBuilder: (BuildContext context, int i) {
          final bool active = i == _current;
          return GestureDetector(
            onTap: () => setState(() => _current = i),
            child: Container(
              width: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadiusSm),
                border: Border.all(
                  color: active ? scheme.primary : scheme.outlineVariant,
                  width: active ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusSm - 1),
                child: Image(
                  image: AuthNetworkImage(_images[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusRow(
    ColorScheme scheme,
    ({String label, Color bg, Color fg}) badge,
  ) {
    return Wrap(
      spacing: kListGap,
      runSpacing: kListGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: badge.bg,
            borderRadius: BorderRadius.circular(kRadiusSm),
          ),
          child: Text(badge.label,
              style: TextStyle(
                  color: badge.fg, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
        _chip(scheme, '尺寸 $_size'),
        _chip(scheme, '$_count 张'),
      ],
    );
  }

  Widget _chip(ColorScheme scheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Text(text,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
    );
  }

  Widget _buildPromptBlock(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(kCardGap),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.format_quote, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('提示词 Prompt',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant)),
              const Spacer(),
              TextButton.icon(
                onPressed: _prompt.isEmpty ? null : _copyPrompt,
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('复制', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            _prompt.isEmpty ? '（无提示词）' : _prompt,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChips(ColorScheme scheme) {
    return Wrap(
      spacing: kListGap,
      runSpacing: kListGap,
      children: <Widget>[
        _chip(scheme, '模型 ${_model.isEmpty ? '未知' : _model}'),
        _chip(scheme, '消耗 $_points 点'),
        if (_createdAt.isNotEmpty) _chip(scheme, _createdAt),
      ],
    );
  }

  Widget _buildRefs(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.collections_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('所用参考图（${_refs.length} 张）',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: kListGap),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _refs.length,
            separatorBuilder: (_, _) => const SizedBox(width: kListGap),
            itemBuilder: (BuildContext context, int i) {
              return GestureDetector(
                onTap: () => _openGallery(_refs, i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  child: SizedBox(
                    width: 72,
                    child: Image(
                      image: AuthNetworkImage(_refs[i]),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildError(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(kCardGap),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: kListGap),
          Expanded(
            child: SelectableText(
              _error,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
