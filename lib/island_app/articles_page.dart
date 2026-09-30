import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 文章分页加载回调（默认走 [ApiClient.getArticles]）。
typedef ArticlesLoader =
    Future<ArticlesData> Function({
  int page,
  String sort,
  String query,
});

/// 文章详情加载回调（默认走 [ApiClient.getArticleDetail]）。
typedef ArticleDetailLoader = Future<Map<String, dynamic>> Function(int id);

/// 文章列表页：官方文章（对齐网页 /articles）。
class ArticlesPage extends StatelessWidget {
  const ArticlesPage({super.key, this.loader, this.detailLoader});

  final ArticlesLoader? loader;
  final ArticleDetailLoader? detailLoader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('官方文章'), centerTitle: true),
      body: ArticlesBody(loader: loader, detailLoader: detailLoader),
    );
  }
}

/// 文章列表主体（独立组件便于测试）。
class ArticlesBody extends StatefulWidget {
  const ArticlesBody({super.key, this.loader, this.detailLoader});

  final ArticlesLoader? loader;
  final ArticleDetailLoader? detailLoader;

  @override
  State<ArticlesBody> createState() => _ArticlesBodyState();
}

class _ArticlesBodyState extends State<ArticlesBody> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  String _sort = 'new';
  String _query = '';
  String? _error;

  ArticlesLoader get _loader => widget.loader ?? ApiClient.instance.getArticles;

  ArticleDetailLoader get _detailLoader =>
      widget.detailLoader ?? ApiClient.instance.getArticleDetail;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = await _loader(page: page, sort: _sort, query: _query);
      if (!mounted) return;
      setState(() {
        if (reset) _items = <Map<String, dynamic>>[];
        _items = <Map<String, dynamic>>[..._items, ...result.items];
        _page = page;
        _noMore = !result.hasNext;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = '$e';
      });
    }
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load(reset: true);
  }

  void _openDetail(Map<String, dynamic> a) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleDetailPage(
          articleId: (a['id'] as num).toInt(),
          loader: _detailLoader,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// 头部：搜索框 + 排序胶囊（最新/最早/最近更新）。
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索文章标题 / 摘要 / 正文',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _query = '';
                        _reload();
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (v) {
              if (v.trim() == _query) return;
              _query = v.trim();
              _reload();
            },
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final (key, label) in const <(String, String)>[
                  ('new', '最新'),
                  ('old', '最早'),
                  ('updated', '最近更新'),
                ]) ...[
                  _SortPill(
                    label: label,
                    selected: _sort == key,
                    onTap: () {
                      if (_sort == key) return;
                      _sort = key;
                      _reload();
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LoadMoreListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      hasMore: !_noMore && _items.isNotEmpty,
      onLoadMore: () => _load(),
      onRefresh: () => _load(reset: true),
      loading: _loading,
      error: _error == null ? null : '加载失败',
      onRetry: _reload,
      empty: EmptyState(
        icon: Icons.article_outlined,
        title: _query.isEmpty ? '暂无文章' : '没有找到相关文章',
      ),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final a = _items[index];
        return ListTile(
          onTap: () => _openDetail(a),
          leading: _coverThumb(context, a),
          title: Text(
            (a['title'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if ((a['summary'] ?? '').toString().isNotEmpty)
                  Text(
                    (a['summary'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${a['author_name'] ?? ''} · ${formatRelativeTime((a['created_at'] ?? '').toString())}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _coverThumb(BuildContext context, Map<String, dynamic> a) {
    final cover = (a['cover'] ?? '').toString();
    if (cover.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.article_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        ServerConfig.resolveUrl(cover),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 48,
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.article_outlined,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

/// 排序胶囊。
class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
        ),
      ),
    );
  }
}

/// 文章详情页：标题 + 作者/时间 + 封面 + 正文 HTML。
class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId, this.loader});

  final int articleId;
  final ArticleDetailLoader? loader;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  Map<String, dynamic>? _article;
  bool _loading = true;
  String? _error;

  ArticleDetailLoader get _loader =>
      widget.loader ?? ApiClient.instance.getArticleDetail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await _loader(widget.articleId);
      if (!mounted) return;
      setState(() {
        _article = a;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文章'), centerTitle: true),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(onRetry: _load);
    }
    final a = _article!;
    final cover = (a['cover'] ?? '').toString();
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            (a['title'] ?? '').toString(),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '${a['author_name'] ?? ''}'
            '${(a['created_at'] ?? '').toString().isEmpty ? '' : ' · ${formatDateTime((a['created_at'] ?? '').toString())}'}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
          if (cover.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ServerConfig.resolveUrl(cover),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Html(
            data: (a['content'] ?? '').toString(),
            extensions: <HtmlExtension>[TableHtmlExtension()],
          ),
        ],
      ),
    );
  }
}
