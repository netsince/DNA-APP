import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/points_page.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/auth_image.dart';
import 'package:dna/island_app/utils/points_format.dart';

/// 生图工作台（App 端）：提示词 + 模型 + 张数 + 宽高比 + 参考图，
/// 提交生成任务后轮询完成，下方展示历史生成记录。
class ImageGenBody extends StatefulWidget {
  const ImageGenBody({super.key, this.onRequireLogin, this.loadSignal});

  /// 未登录时「去登录」回调：由外壳切换到「我」页展示登录表单，
  /// 而不是另起一个独立的登录页，避免出现两个登录入口。
  final VoidCallback? onRequireLogin;

  /// 首次激活信号：因为本页常驻在 IndexedStack 中（应用启动即构建），
  /// 若在 initState 里立刻请求会因登录态尚未就绪而 401。
  /// 由外壳在切到「生图」tab 时触发一次（自增），首次收到后才拉取元数据与历史。
  final ValueListenable<int>? loadSignal;

  @override
  State<ImageGenBody> createState() => _ImageGenBodyState();
}

class _ImageGenBodyState extends State<ImageGenBody> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _models = const <Map<String, dynamic>>[];
  Decimal _balance = Decimal.zero;
  int _maxRefs = 5;

  int? _modelId;
  int _count = 1;
  String _aspect = 'auto';
  List<XFile> _refs = <XFile>[];
  bool _pickingRefs = false;
  bool _submitting = false;

  Timer? _pollTimer;
  final Set<int> _activeTaskIds = <int>{};

  final List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  bool _logsLoading = false;
  bool _logsNoMore = false;
  bool _logsLoadingMore = false;
  int _logsPage = 0;

  /// 防止首次激活信号重复触发加载。
  bool _loadInFlight = false;

  @override
  void initState() {
    super.initState();
    // 本页常驻 IndexedStack：应用启动即构建，但登录态可能尚未就绪。
    // 若提供了 loadSignal，等外壳切到「生图」tab 后再加载，避免启动 401；
    // 否则（独立使用/测试）直接加载。
    final signal = widget.loadSignal;
    if (signal == null) {
      _load();
    } else {
      signal.addListener(_onLoadSignal);
    }
  }

  void _onLoadSignal() {
    if (_loadInFlight) return;
    _loadInFlight = true;
    _load().whenComplete(() => _loadInFlight = false);
  }

  @override
  void dispose() {
    widget.loadSignal?.removeListener(_onLoadSignal);
    _pollTimer?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meta = await ApiClient.instance.getImageGenMeta();
      if (!mounted) return;
      final models = (meta['models'] is List)
          ? (meta['models'] as List).whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _models = models;
        _balance = parsePoints(meta['balance']);
        _maxRefs = (meta['max_references'] as num?)?.toInt() ?? 5;
        _modelId ??= models.isNotEmpty ? (models.first['id'] as num?)?.toInt() : null;
        _loading = false;
      });
      await _loadLogs(reset: true);
      _ensurePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  // ---------- 参考图 ----------
  Future<void> _pickRefs() async {
    if (_pickingRefs) return;
    setState(() => _pickingRefs = true);
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (!mounted) return;
      final remaining = _maxRefs - _refs.length;
      setState(() {
        _refs = [..._refs, ...picked.take(remaining)];
      });
    } catch (_) {
      if (!mounted) return;
      _snack('选择参考图失败');
    } finally {
      if (mounted) setState(() => _pickingRefs = false);
    }
  }

  Future<List<Map<String, dynamic>>> _buildRefPayload() async {
    final payload = <Map<String, dynamic>>[];
    for (final f in _refs) {
      try {
        final bytes = await f.readAsBytes();
        final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'png';
        payload.add(<String, dynamic>{
          'filename': f.name,
          'mimetype': _mimeOf(ext),
          'data_b64': base64Encode(bytes),
        });
      } catch (_) {
        // 跳过无法读取的参考图
      }
    }
    return payload;
  }

  String _mimeOf(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'png':
      default:
        return 'image/png';
    }
  }

  // ---------- 生成 ----------
  Future<void> _generate() async {
    if (!_loggedIn) {
      _snack('请先登录后使用生图');
      return;
    }
    if (_submitting || _activeTaskIds.isNotEmpty) {
      _snack('已有进行中的生图任务，请等待完成');
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _snack('请输入提示词');
      return;
    }
    final modelId = _modelId;
    if (modelId == null) {
      _snack('请选择生图模型');
      return;
    }
    // 预估算积分，点数不足先弹引导（对齐网页版：不足时给「去获取积分」）。
    final model = _models.where((m) => (m['id'] as num?)?.toInt() == modelId).firstOrNull;
    final perImage = parsePoints(model?['points_per_image']);
    final estimated = perImage * Decimal.fromInt(_count);
    if (estimated > Decimal.zero && _balance < estimated) {
      _showInsufficientPoints(estimated);
      return;
    }
    setState(() => _submitting = true);
    try {
      final references = await _buildRefPayload();
      final taskId = await ApiClient.instance.generateImage(
        prompt: prompt,
        modelId: modelId,
        size: _aspect,
        count: _count,
        references: references,
      );
      if (!mounted) return;
      setState(() {
        _activeTaskIds.add(taskId);
        _promptController.clear();
        _refs = <XFile>[];
      });
      _ensurePolling();
    } catch (e) {
      if (!mounted) return;
      _snack('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 点数不足弹窗：带「去获取积分」引导（对齐网页版模态）。
  void _showInsufficientPoints(Decimal estimated) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('点数不足'),
        content: Text('本次预计消耗 ${formatPoints(estimated)} 点，当前余额 ${formatPoints(_balance)} 点。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PointsPage()),
              );
            },
            child: const Text('去获取积分'),
          ),
        ],
      ),
    );
  }

  // ---------- 轮询 ----------
  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 4), (_) => _pollTasks());
    _pollTasks();
  }

  Future<void> _pollTasks() async {
    if (!mounted || _activeTaskIds.isEmpty) return;
    try {
      final tasks = await ApiClient.instance.getActiveImageGenTasks();
      if (!mounted) return;
      final returned = tasks.map((t) => (t['id'] as num?)?.toInt() ?? -1).toSet();
      for (final id in [..._activeTaskIds]) {
        if (!returned.contains(id)) {
          _activeTaskIds.remove(id);
          _onTaskGone(id);
        }
      }
    } catch (_) {
      // 轮询失败静默，下轮再试
    }
  }

  Future<void> _onTaskGone(int taskId) async {
    try {
      final detail = await ApiClient.instance.getImageGenTaskDetail(taskId);
      if (!mounted) return;
      final status = (detail['status'] ?? '').toString();
      final hasBalance = detail['balance'] != null;
      final balance = parsePoints(detail['balance']);
      setState(() {
        if (hasBalance) _balance = balance;
      });
      if (status == 'succeeded') {
        final spent = parsePoints(detail['points_spent']);
        _snack('生图完成，消耗 ${formatPoints(spent)} 点');
        await _loadLogs(reset: true);
      } else {
        _snack('生图失败：${detail['error'] ?? '未知错误'}');
      }
    } catch (_) {
      if (mounted) await _loadLogs(reset: true);
    }
  }

  // ---------- 历史日志 ----------
  Future<void> _loadLogs({bool reset = false}) async {
    if (_logsLoadingMore || (!reset && _logsNoMore)) return;
    if (!mounted) return;
    setState(() {
      if (reset) {
        _logsLoading = true;
        _logsPage = 0;
        _logsNoMore = false;
      }
      _logsLoadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _logsPage + 1;
      final result = await ApiClient.instance.getImageGenLogs(page: page);
      if (!mounted) return;
      setState(() {
        if (reset) _logs.clear();
        _logs.addAll(result.items);
        _logsPage = page;
        _logsNoMore = result.items.isEmpty || !result.hasNext;
        _logsLoading = false;
        _logsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _logsLoading = false;
        _logsLoadingMore = false;
      });
    }
  }

  void _openLog(Map<String, dynamic> log) {
    final images = log['images'];
    if (images is! List || images.isEmpty) return;
    final urls = images.map((e) => e.toString()).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AuthImageViewer(urls: urls, log: log),
      ),
    );
  }

  /// 由生成记录里的 `size`（如 "1024x1024"）推导宽高比；解析失败回退 3:4。
  static double _logAspect(Map<String, dynamic> log) {
    final size = (log['size'] ?? '').toString().toLowerCase();
    if (size.contains('x')) {
      final parts = size.split('x');
      final w = double.tryParse(parts[0].trim());
      final h = parts.length > 1 ? double.tryParse(parts[1].trim()) : null;
      if (w != null && h != null && h > 0) return w / h;
    }
    return 3 / 4;
  }

  /// 生图历史瀑布流：不显示分辨率/模型名，仅图片卡片，按原图比例高低错落。
  static Widget _buildMasonry(
    BuildContext context,
    List<Map<String, dynamic>> logs, {
    required void Function(Map<String, dynamic>) onTap,
    ScrollController? controller,
    bool shrinkWrap = false,
    bool addLoadingMore = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final itemCount = logs.length + (addLoadingMore ? 1 : 0);
    return MasonryGridView.count(
      controller: controller,
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.all(8),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i >= logs.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final log = logs[i];
        final firstImage = (log['first_image'] ?? '').toString();
        final aspect = _logAspect(log);
        return InkWell(
          onTap: () => onTap(log),
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(color: scheme.surfaceContainerHighest),
                  Image(
                    image: AuthNetworkImage(firstImage),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                    frameBuilder: (context, child, frame, sync) {
                      if (frame == null) {
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            child,
                            const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ],
                        );
                      }
                      return child;
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_awesome_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('登录后即可使用生图'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.onRequireLogin ??
                  () => _snack('请先在侧边栏「我」页登录'),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _models.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: <Widget>[
          _buildBalanceBar(context),
          const SizedBox(height: 12),
          _buildWorkbench(context),
          const SizedBox(height: 20),
          _buildHistoryHeader(context),
          const SizedBox(height: 8),
          ..._buildHistory(context),
        ],
      ),
    );
  }

  Widget _buildBalanceBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.stars_outlined, color: scheme.primary),
        const SizedBox(width: 6),
        Text('当前点数：${formatPoints(_balance)}',
            style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PointsPage()),
          ),
          icon: const Icon(Icons.redeem_outlined, size: 18),
          label: const Text('获取点数'),
        ),
      ],
    );
  }

  Widget _buildWorkbench(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('生图工作台',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '描述你想生成的画面…使用参考图时可用「图片1」指代',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: _buildModelDropdown(context)),
                const SizedBox(width: 10),
                Expanded(child: _buildCountDropdown(context)),
              ],
            ),
            const SizedBox(height: 12),
            _buildAspectSelector(context),
            const SizedBox(height: 12),
            _buildRefsSection(context, scheme),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_submitting || _activeTaskIds.isNotEmpty)
                    ? null
                    : _generate,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_activeTaskIds.isNotEmpty
                    ? '生成中…'
                    : (_submitting ? '提交中…' : '生成')),
              ),
            ),
            if (_activeTaskIds.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(child: Text('正在生成，请稍候…')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelDropdown(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: _modelId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '模型',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: _models.map((m) {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        final name = (m['display_name'] ?? '').toString();
        final pts = parsePoints(m['points_per_image']);
        return DropdownMenuItem<int>(
          value: id,
          child: Text('$name（${formatPoints(pts)} 点/张）', overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (v) => setState(() => _modelId = v),
    );
  }

  Widget _buildCountDropdown(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: _count,
      decoration: const InputDecoration(
        labelText: '张数',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<int>>[
        const DropdownMenuItem<int>(value: 1, child: Text('1 张')),
        const DropdownMenuItem<int>(value: 2, child: Text('2 张')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _count = v);
      },
    );
  }

  Widget _buildAspectSelector(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const aspects = <String>['auto', '1:1', '3:2', '2:3', '4:3', '3:4', '16:9', '9:16'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('宽高比',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: aspects.map((a) {
            final selected = _aspect == a;
            return ChoiceChip(
              label: Text(a),
              selected: selected,
              onSelected: (_) => setState(() => _aspect = a),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRefsSection(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('参考图（最多 $_maxRefs 张）',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (_refs.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < _refs.length; i++)
                _buildRefThumb(context, _refs[i], i),
            ],
          ),
        if (_refs.length < _maxRefs)
          OutlinedButton.icon(
            onPressed: _pickingRefs ? null : _pickRefs,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(_pickingRefs ? '选择中…' : '添加参考图'),
          ),
      ],
    );
  }

  Widget _buildRefThumb(BuildContext context, XFile file, int index) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(file.path),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: () => setState(() => _refs.removeAt(index)),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 2,
          bottom: 0,
          child: Text('图片${index + 1}',
              style: TextStyle(fontSize: 10, color: scheme.onSurface)),
        ),
      ],
    );
  }

  Widget _buildHistoryHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text('我的生成记录',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ImageGenHistoryPage(),
              ),
            );
          },
          child: const Text('全部记录 ›'),
        ),
      ],
    );
  }

  List<Widget> _buildHistory(BuildContext context) {
    if (_logsLoading && _logs.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_logs.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('还没有生成记录，填写提示词开始创作吧。')),
        ),
      ];
    }
    return <Widget>[
      _buildMasonry(context, _logs, onTap: _openLog, shrinkWrap: true),
      if (_logsLoadingMore)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      // 分页：还有更多时点击「加载更多」。
      if (!_logsNoMore)
        Center(
          child: TextButton(
            onPressed: _logsLoadingMore ? null : _loadLogs,
            child: const Text('加载更多'),
          ),
        ),
    ];
  }
}

/// 生图产出的全屏查看器（带认证头加载）。
class _AuthImageViewer extends StatefulWidget {
  const _AuthImageViewer({required this.urls, required this.log});

  final List<String> urls;
  final Map<String, dynamic> log;

  @override
  State<_AuthImageViewer> createState() => _AuthImageViewerState();
}

class _AuthImageViewerState extends State<_AuthImageViewer> {
  final PageController _pageController = PageController();
  int _current = 0;
  bool _downloading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 下载当前页原图到系统临时目录（WebP 原样保存，如需 PNG 可后续扩展）。
  Future<void> _downloadCurrent() async {
    if (_downloading) return;
    final url = widget.urls[_current];
    setState(() => _downloading = true);
    try {
      final bytes = await fetchAuthImageBytes(url);
      final safePrompt = (widget.log['prompt'] ?? 'artwork')
          .toString()
          .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
      final name = '${safePrompt.length > 30 ? safePrompt.substring(0, 30) : safePrompt}_${_current + 1}.webp';
      final file = await File('${Directory.systemTemp.path}${Platform.pathSeparator}$name')
          .writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载：${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('生图预览', style: const TextStyle(fontSize: 16)),
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
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) {
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
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(16),
          child: Text(
            '提示词：${log['prompt'] ?? ''}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// 生图历史全量页（对齐网页版 `/image-gen/logs`）：独立、可翻页地展示
/// 全部生成记录，点任意一条进入全屏详情查看。
class ImageGenHistoryPage extends StatefulWidget {
  const ImageGenHistoryPage({super.key});

  @override
  State<ImageGenHistoryPage> createState() => _ImageGenHistoryPageState();
}

class _ImageGenHistoryPageState extends State<ImageGenHistoryPage> {
  final ScrollController _controller = ScrollController();
  final List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.pixels >=
        _controller.position.maxScrollExtent - 400) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) {
        _loading = true;
        _noMore = false;
        _page = 0;
      }
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = await ApiClient.instance.getImageGenLogs(page: page);
      if (!mounted) return;
      setState(() {
        if (reset) _logs.clear();
        _logs.addAll(result.items);
        _page = page;
        _noMore = result.items.isEmpty || !result.hasNext;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _openLog(Map<String, dynamic> log) {
    final images = log['images'];
    if (images is! List || images.isEmpty) return;
    final urls = images.map((e) => e.toString()).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AuthImageViewer(urls: urls, log: log),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的生图记录'), centerTitle: true),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.photo_library_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('还没有生成记录，去工作台创作第一张吧。'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: _ImageGenBodyState._buildMasonry(
        context,
        _logs,
        onTap: _openLog,
        controller: _controller,
        addLoadingMore: _loadingMore,
      ),
    );
  }
}
