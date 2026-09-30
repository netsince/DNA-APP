import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 站长推荐加载回调（默认走 [ApiClient.getRecommendations]）。
typedef RecommendationsLoader = Future<RecommendationsData> Function();

/// 站长推荐页：角色卡与创作者按推荐顺序瀑布流排布（对齐网页 /recommend）。
class RecommendPage extends StatelessWidget {
  const RecommendPage({super.key, this.loader});

  final RecommendationsLoader? loader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('站长推荐'), centerTitle: true),
      body: RecommendBody(loader: loader),
    );
  }
}

/// 站长推荐主体（独立组件便于测试）。
class RecommendBody extends StatefulWidget {
  const RecommendBody({super.key, this.loader});

  final RecommendationsLoader? loader;

  @override
  State<RecommendBody> createState() => _RecommendBodyState();
}

class _RecommendBodyState extends State<RecommendBody> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  RecommendationsLoader get _loader =>
      widget.loader ?? ApiClient.instance.getRecommendations;

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
      final result = await _loader();
      if (!mounted) return;
      setState(() {
        _items = result.items;
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

  void _openCard(Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: (data['id'] ?? '').toString()),
      ),
    );
  }

  void _openUser(Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          username: (data['username'] ?? '').toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(onRetry: _load);
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.workspaces_outline,
        title: '暂无推荐内容。',
      );
    }
    // 宽屏（横屏/桌面）自适应多列并排，窄屏保持单列；统一支持下拉刷新。
    return AppRefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return _buildSingleColumn();
          }
          return _buildColumns(constraints.maxWidth);
        },
      ),
    );
  }

  Widget _itemWidget(Map<String, dynamic> it) {
    if (it['kind'] == 'card') {
      return _RecommendCard(
        data: it['data'],
        note: (it['note'] ?? '').toString(),
        onTap: () => _openCard(it['data']),
      );
    }
    return _RecommendUser(
      data: it['data'],
      note: (it['note'] ?? '').toString(),
      cardCount: (it['card_count'] as num?)?.toInt() ?? 0,
      onTap: () => _openUser(it['data']),
    );
  }

  /// 窄屏：单列列表。
  Widget _buildSingleColumn() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final it in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _itemWidget(it),
          ),
      ],
    );
  }

  /// 宽屏：自适应多列瀑布流（最多 6 列，交替放入当前最矮的列）。
  ///
  /// 列数随可用宽度增加：保证每列至少约 [minColWidth] 宽，卡片不会太小；
  /// 列之间与卡片之间都保留 [gap] 间隔。
  Widget _buildColumns(double width) {
    const double gap = 16;
    const double minColWidth = 210;
    final int columns = (width / minColWidth).floor().clamp(2, 6);
    final double colWidth = (width - 16 * 2 - gap * (columns - 1)) / columns;
    final List<List<Widget>> columnItems = <List<Widget>>[
      for (var i = 0; i < columns; i++) <Widget>[],
    ];
    final List<double> heights = <double>[for (var i = 0; i < columns; i++) 0];
    for (final it in _items) {
      final bool isCard = it['kind'] == 'card';
      final String note = (it['note'] ?? '').toString();
      // 估算高度用于平衡各列：卡片按 3:4 封面 + 文字区；创作者按横条高度。
      final double estimated = isCard
          ? colWidth * 4 / 3 + 130 + (note.isNotEmpty ? 44 : 0)
          : 84 + (note.isNotEmpty ? 40 : 0);
      int target = 0;
      for (var i = 1; i < columns; i++) {
        if (heights[i] < heights[target]) target = i;
      }
      columnItems[target].add(
        Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: _itemWidget(it),
        ),
      );
      heights[target] += estimated;
    }
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 列与列之间保留 [gap] 横向间隔。
          for (var i = 0; i < columnItems.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columnItems[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 推荐角色卡：复用 [CardTile] 展示封面/名称/作者/简介/统计，
/// 下方叠加站长推荐语。
class _RecommendCard extends StatelessWidget {
  const _RecommendCard({
    required this.data,
    required this.note,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CardTile(card: data, onTap: onTap),
        if (note.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.star_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 推荐创作者：头像 + 昵称 + 角色卡数 + 推荐语。
class _RecommendUser extends StatelessWidget {
  const _RecommendUser({
    required this.data,
    required this.note,
    required this.cardCount,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final String note;
  final int cardCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = (data['nickname'] ?? '').toString();
    final username = (data['username'] ?? '').toString();
    final avatar = (data['avatar'] ?? '').toString();
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Avatar(avatar: avatar, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username · $cardCount 张角色卡',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (note.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurface),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}
