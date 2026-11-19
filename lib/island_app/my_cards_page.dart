import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/card_payload.dart';
import 'package:dna/island_app/card_publish_start_page.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/island_app/widgets/status_badge.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/island_app/card_publish_page.dart';

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
  /// 分页状态（加载中 / 加载更多 / 没有更多 / 页码 / 错误）统一由
  /// [PagedController] 管，页面只提供「怎么取一页」。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final Map<String, dynamic> data = await ApiClient.instance.getMyCards(
            page: page,
          );
          final Object? raw = data['items'];
          final List<Map<String, dynamic>> items = raw is List
              ? raw
                    .whereType<Map>()
                    .map((Map e) => e.map((k, v) => MapEntry(k.toString(), v)))
                    .toList()
              : <Map<String, dynamic>>[];
          return PagedResult<Map<String, dynamic>>(
            items: items,
            hasMore: data['has_next'] == true,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        // 请求失败不能落到「你还没有发布角色卡」这个空态上，
        // 也不能把翻页失败当成首屏失败（控制器只在列表为空时置错误）。
        firstLoadError: '角色卡列表加载失败，请稍后重试',
      );

  @override
  void initState() {
    super.initState();
    _paged.refresh();
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  void _openDetail(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    if (id.isEmpty) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: id)));
    if (mounted) _paged.refresh();
  }

  /// 编辑已发布的角色卡：拉详情 → 转成本地 TA → 打开**软件本体那个编辑器**，
  /// 保存 = 整份替换并重新提审（与发布同一套映射）。
  Future<void> _edit(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final Map<String, dynamic> detail = await ApiClient.instance
          .getCardDetail(id);
      final TA ta = await taFromCardDetail(detail);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CommunityCardEditorPage(
            ta: ta,
            title: '编辑角色卡',
            saveLabel: '保存并重新提审',
            onSave: (TA edited) async {
              await ApiClient.instance.editCard(
                id,
                taToPublishPayload(
                  edited,
                  images: await taImageDataUrls(edited),
                ),
              );
            },
          ),
        ),
      );
      if (mounted) _paged.refresh();
    } catch (e) {
      _snack('打开编辑器失败：$e');
    }
  }

  Future<void> _resubmit(Map<String, dynamic> card) async {
    final id = (card['id'] ?? '').toString();
    try {
      await ApiClient.instance.resubmitCard(id);
      if (!mounted) return;
      _snack('已重新提审，等待审核');
      _paged.refresh();
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
      _paged.refresh();
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
      _paged.refresh();
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
      appBar: AppBar(title: const Text('我的角色卡')),
      body: LoadMoreListView(
        loading: _paged.isLoading,
        itemCount: _paged.items.length,
        hasMore: _paged.hasMore && _paged.items.isNotEmpty,
        onLoadMore: () => _paged.loadMore(),
        onRefresh: () => _paged.refresh(),
        // 失败 → 共享错误态 + 重试，而不是「你还没有发布角色卡」。
        error: _paged.error,
        onRetry: () => _paged.refresh(),
        // 行直接贴在 surface 上：结构同构、需要线性扫读的集合用 list，
        // 而不是每行一张卡（审计 3.3）。横向内边距交给 ListTile（16）。
        padding: EdgeInsets.zero,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: AppSpacing.lg),
        empty: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.badge_outlined,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                '你还没有发布角色卡',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
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
        itemBuilder: (context, index) => _cardTile(_paged.items[index]),
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

    // 裸 ListTile：每行本就是这个集合里的一行，不是独立的内容单元，
    // 套卡片只会让 5 张卡挤满一屏（审计 3.3）。行间距由 Divider 承担。
    return ListTile(
      contentPadding: AppInsets.tile,
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (intro.isNotEmpty)
            Text(intro, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: <Widget>[
              StatusChip(status: status),
              // 置顶 / 已隐藏是**只读元信息**，用共享标签；不再是带 raw color 的另一个类。
              if (pinned) const StatusBadge(label: '置顶'),
              if (hidden) const StatusBadge(label: '已隐藏'),
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
          const PopupMenuItem<String>(value: 'detail', child: Text('查看详情')),
          const PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
          if (rejected)
            const PopupMenuItem<String>(
              value: 'resubmit',
              child: Text('重新提审'),
            ),
          // 只有「已通过」的卡能置顶（服务端同样校验）。
          if (status == 'approved')
            PopupMenuItem<String>(
              value: 'pin',
              child: Text(pinned ? '取消置顶' : '置顶到主页'),
            ),
          PopupMenuItem<String>(
            value: 'hidden',
            child: Text(hidden ? '取消隐藏' : '隐藏'),
          ),
        ],
      ),
      onTap: () => _openDetail(card),
    );
  }
}

/// 审核状态小徽章：status → 语义色调的**薄适配**，视觉交给共享 [StatusBadge]。
///
/// 保留这个公开类名是为了不动既有调用点；具体怎么画（色对 / 字号 / 圆角 /
/// 无 ink）只有 [StatusBadge] 一份实现。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (String label, BadgeTone tone) = switch (status) {
      'approved' => ('已通过', BadgeTone.positive),
      'rejected' => ('已拒绝', BadgeTone.danger),
      _ => ('审核中', BadgeTone.caution),
    };
    return StatusBadge(
      label: label,
      tone: tone,
      semanticLabel: '审核状态：$label',
    );
  }
}
