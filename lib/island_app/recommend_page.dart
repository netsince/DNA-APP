import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/user_badge.dart';

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
        builder: (_) =>
            UserProfilePage(username: (data['username'] ?? '').toString()),
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
      return const EmptyState(icon: Icons.workspaces_outline, title: '暂无推荐内容。');
    }
    // 宽屏（横屏/桌面）自适应多列并排，窄屏保持单列；统一支持下拉刷新。
    return AppRefreshIndicator(
      onRefresh: _load,
      //宽屏自适应多列；**手机竖屏也给双列** ——单列时一张3:4封面的卡片
      //会横跨整屏、又高又大，正是用户反馈「一张卡占满很大屏幕」的成因。
      //窄屏列宽下限放宽到150，保证390宽也能排下2列。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool narrow = constraints.maxWidth < 600;
          return _buildColumns(
            constraints.maxWidth,
            minColWidth: narrow ? 150 : 210,
            maxColumns: narrow ? 2 : 6,
          );
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

  ///瀑布流：自适应多列，交替放入当前最矮的列。
  ///
  ///手机竖屏也是**双列**（单列时3:4封面会横跨整屏、占满很大一块）；
  ///桌面按宽度自然增加到6列。
  Widget _buildColumns(
    double width, {
    double minColWidth = 210,
    int maxColumns = 6,
  }) {
    const double gap = 16;
    final int columns = (width / minColWidth).floor().clamp(2, maxColumns);
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
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
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
    final username = (data['username'] ?? '').toString();
    final avatar = (data['avatar'] ?? '').toString();
    //窄列（手机双列时每列约170）放不下「头像+文字+箭头」的横排，
    //换成头像在上、文字在下的竖排；宽列保持原来的横条。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 220;
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Avatar(avatar: avatar, radius: 20),
                        const SizedBox(height: 8),
                        _buildTexts(context, scheme, username, compact: true),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        Avatar(avatar: avatar, radius: 24),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTexts(context, scheme, username)),
                        Icon(Icons.chevron_right, color: scheme.outlineVariant),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  ///创作者名称 / @用户名·卡数 /推荐语。窄列时推荐语只留1行，避免把卡片撑太高。
  Widget _buildTexts(
    BuildContext context,
    ColorScheme scheme,
    String username, {
    bool compact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UserBadge.fromUser(
          data,
          fallbackName: username,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          '@$username · $cardCount张角色卡',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (note.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            note,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
          ),
        ],
      ],
    );
  }
}
