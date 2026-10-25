import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/image_gen_detail_page.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/auth_image.dart';
import '../theme/tokens.dart';

/// 生成失败记录页（App 端）：列出自己**所有失败的生成**及其完整信息。
///
/// 用户反馈：生图失败之后只能看到一句错误提示，看不到当时填的提示词、选的模型/尺寸/张数、
/// 传了哪些参考图 —— 想复现或改提示词都无从下手。这里单独成页：每条都带上这些信息，
/// 点进去是完整详情（含「同款生成」，可把提示词回填到工作台重试）。
///
/// 数据来自 `/api/v1/image-gen/logs?status=failed`：服务端按状态过滤并分页，
/// 所以这里翻的都是失败记录，不会被成功记录稀释。
class ImageGenFailedPage extends StatefulWidget {
  const ImageGenFailedPage({super.key});

  @override
  State<ImageGenFailedPage> createState() => _ImageGenFailedPageState();
}

class _ImageGenFailedPageState extends State<ImageGenFailedPage> {
  final ScrollController _controller = ScrollController();
  final List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;
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
        _controller.position.maxScrollExtent - kLoadMoreThreshold) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) {
        _loading = true;
        _noMore = false;
        _error = null;
        _page = 0;
      }
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = await ApiClient.instance.getImageGenLogs(
        page: page,
        status: 'failed',
      );
      if (!mounted) return;
      setState(() {
        if (reset) _logs.clear();
        _logs.addAll(result.items);
        _page = page;
        _noMore = result.items.isEmpty || !result.hasNext;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = '$e';
      });
    }
  }

  /// 打开完整详情；详情页的「同款生成」会把提示词 pop 回来，这里继续往上抛给工作台
  /// （本页是盖在工作台之上的，所以先 pop 自己）。
  Future<void> _openLog(Map<String, dynamic> log) async {
    final String? prompt = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => ImageGenDetailPage(log: log)),
    );
    if (!mounted || prompt == null || prompt.isEmpty) return;
    Navigator.of(context).pop(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生成失败记录'), centerTitle: true),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (_loading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('加载失败：$_error', style: TextStyle(color: scheme.error)),
            const SizedBox(height: kCardGap),
            OutlinedButton(
              onPressed: () => _load(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(kPagePadding),
          child: Text('还没有生成失败的记录。'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.all(kPagePadding),
        itemCount: _logs.length + (_loadingMore ? 1 : 0),
        itemBuilder: (BuildContext context, int i) {
          if (i >= _logs.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final Map<String, dynamic> log = _logs[i];
          return ImageGenFailedCard(log: log, onTap: () => _openLog(log));
        },
      ),
    );
  }
}

/// 失败记录卡片：提示词 + 模型/尺寸/张数/消耗 + 所用参考图 + 失败原因。
///
/// 单独抽成公开组件是为了能直接写 widget 测试：页面本身要先联网取数据，
/// 在测试里根本进不到"有记录"的状态。
class ImageGenFailedCard extends StatelessWidget {
  const ImageGenFailedCard({super.key, required this.log, this.onTap});

  final Map<String, dynamic> log;
  final VoidCallback? onTap;

  String get _prompt => (log['prompt'] ?? '').toString();
  String get _error => (log['error'] ?? '').toString();
  String get _model => (log['model_name'] ?? '').toString();
  String get _size => (log['size'] ?? 'auto').toString();
  String get _points => (log['points_spent'] ?? '0').toString();
  String get _createdAt => (log['created_at'] ?? '').toString();
  int get _count => (log['count'] as num?)?.toInt() ?? 0;

  List<String> get _refs => log['references'] is List
      ? (log['references'] as List).map((dynamic e) => e.toString()).toList()
      : const <String>[];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: kCardGap),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(kCardGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(kRadiusSm),
                    ),
                    child: Text(
                      '失败',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: kListGap),
                  if (_createdAt.isNotEmpty)
                    Text(
                      _createdAt,
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: kListGap),
              Text(
                _prompt.isEmpty ? '（无提示词）' : _prompt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppFontSize.body, height: AppLineHeight.title),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: kListGap,
                runSpacing: 6,
                children: <Widget>[
                  _chip(scheme, '模型 ${_model.isEmpty ? '未知' : _model}'),
                  _chip(scheme, _size),
                  _chip(scheme, '$_count 张'),
                  _chip(scheme, '消耗 $_points 点'),
                ],
              ),
              if (_refs.isNotEmpty) ...<Widget>[
                const SizedBox(height: kListGap),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _refs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (BuildContext context, int i) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        child: SizedBox(
                          width: 56,
                          child: Image(
                            image: AuthNetworkImage(_refs[i]),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: scheme.surfaceContainerHighest),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_error.isNotEmpty) ...<Widget>[
                const SizedBox(height: kListGap),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(kListGap),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(kRadiusSm),
                  ),
                  child: Text(
                    _error,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontSize: AppFontSize.caption,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme scheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFontSize.tiny, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
