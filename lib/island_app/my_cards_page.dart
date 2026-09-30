import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/card_publish_page.dart';
import 'package:dna/island_app/card_publish_start_page.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';

/// 「我的角色卡」管理页：分页列出自己发布的角色卡。
///
/// 每张卡显示审核状态徽章（审核中/已通过/已拒绝/已隐藏），提供操作：
/// 编辑、重新提审（仅被拒绝）、切换隐藏、查看详情。
class MyCardsPage extends StatefulWidget {
  const MyCardsPage({super.key});

  @override
  State<MyCardsPage> createState() => _MyCardsPageState();
}

class _MyCardsPageState extends State<MyCardsPage> {
  final List<Map<String, dynamic>> _cards = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final data = await ApiClient.instance.getMyCards(page: reset ? 1 : _page + 1);
      if (!mounted) return;
      final raw = data['items'];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (reset) _cards.clear();
        _cards.addAll(items);
        _page = reset ? 1 : _page + 1;
        _noMore = items.isEmpty || data['has_next'] != true;
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

  void _openDetail(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: id)),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _edit(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardPublishPage(editCardId: id),
      ),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _resubmit(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    try {
      await ApiClient.instance.resubmitCard(id);
      if (!mounted) return;
      _snack('已重新提审，等待审核');
      _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      _snack('重新提审失败：$e');
    }
  }

  Future<void> _toggleHidden(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    try {
      final hidden = await ApiClient.instance.toggleCardHidden(id);
      if (!mounted) return;
      _snack(hidden ? '已隐藏' : '已取消隐藏');
      _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      _snack('操作失败：$e');
    }
  }

  /// 置顶 / 取消置顶。失败（名额已满 / 未通过）时服务端会给出可读原因，直接展示。
  Future<void> _togglePin(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final pinned = await ApiClient.instance.toggleCardPinned(id);
      if (!mounted) return;
      _snack(pinned ? '已置顶到主页最前' : '已取消置顶');
      _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      _snack('$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的角色卡'), centerTitle: true),
      body: LoadMoreListView(
        loading: _loading,
        itemCount: _cards.length,
        hasMore: !_noMore && _cards.isNotEmpty,
        onLoadMore: () => _load(),
        onRefresh: () => _load(reset: true),
        padding: const EdgeInsets.all(8),
        separatorBuilder: (_, _) => const SizedBox.shrink(),
        empty: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.badge_outlined, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('你还没有发布角色卡',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CardPublishStartPage(),
                    ),
                  );
                },
                child: const Text('去上传'),
              ),
            ],
          ),
        ),
        itemBuilder: (context, index) => _cardTile(_cards[index]),
      ),
    );
  }

  Widget _cardTile(Map<String, dynamic> card) {
    final name = (card['name'] ?? '').toString();
    final intro = (card['intro'] ?? '').toString();
    final status = (card['status'] ?? 'pending').toString();
    final hidden = card['is_hidden'] == true;
    final pinned = card['pinned'] == true;
    final rejected = status == 'rejected';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (intro.isNotEmpty)
              Text(intro,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: <Widget>[
                StatusChip(status: status),
                if (pinned) const MyCardsChip(label: '置顶', neutral: true),
                if (hidden) const MyCardsChip(label: '已隐藏', neutral: true),
              ],
            ),
          ],
        ),
        isThreeLine: false,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _edit(card);
                break;
              case 'resubmit':
                _resubmit(card);
                break;
              case 'hidden':
                _toggleHidden(card);
                break;
              case 'pin':
                _togglePin(card);
                break;
              case 'detail':
                _openDetail(card);
                break;
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
                value: 'detail', child: Text('查看详情')),
            const PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
            if (rejected)
              const PopupMenuItem<String>(
                  value: 'resubmit', child: Text('重新提审')),
            // 只有「已通过」的卡能置顶（服务端同样校验）。
            if (status == 'approved')
              PopupMenuItem<String>(
                  value: 'pin', child: Text(pinned ? '取消置顶' : '置顶到主页')),
            PopupMenuItem<String>(
                value: 'hidden', child: Text(hidden ? '取消隐藏' : '隐藏')),
          ],
        ),
        onTap: () => _openDetail(card),
      ),
    );
  }
}

/// 审核状态小徽章。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      'approved' => ('已通过', scheme.primaryContainer, scheme.onPrimaryContainer),
      'rejected' => ('已拒绝', scheme.errorContainer, scheme.onErrorContainer),
      _ => ('审核中', scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return MyCardsChip(label: label, background: bg, foreground: fg);
  }
}

class MyCardsChip extends StatelessWidget {
  const MyCardsChip({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.neutral = false,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg = background ?? scheme.surfaceContainerHighest;
    final Color fg = foreground ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg)),
    );
  }
}
