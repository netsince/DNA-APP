import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/theme/tokens.dart';

/// 世界卡的**通用列表页**：给「我的世界卡」「我收藏的世界卡」这类入口复用。
///
/// 和社区栏目里的 [WorldsBody] 的区别：那个带搜索/排序/标签，是「逛」用的；
/// 这个只有一份数据 + 分页，是「看自己的」用的。
///
/// [manageable] 为 true 时（「我的世界卡」）每行额外显示审核状态徽章与
/// 「撤回」入口 —— 之前这里和别人的列表长得一模一样，作者根本看不出自己
/// 的条目是待审核、被拒绝还是已下架，也没有任何撤回的办法。
class WorldsListPage extends StatefulWidget {
  const WorldsListPage({
    super.key,
    required this.title,
    required this.loader,
    this.emptyText = '这里还没有世界卡。',
    this.importSink,
    this.manageable = false,
    this.deleter,
  });

  final String title;

  /// (page) -> 分页对象（items / has_next）。
  final Future<Map<String, dynamic>> Function(int page) loader;

  final String emptyText;

  /// 导入落地用的窄接口；为空时详情页不给导入按钮。
  final WorldImportSink? importSink;

  /// 是否是「我的世界卡」：显示状态徽章与撤回入口。
  final bool manageable;

  /// 撤回回调（测试可注入）。为空时走 [ApiClient.deleteWorld]。
  final Future<void> Function(String id)? deleter;

  @override
  State<WorldsListPage> createState() => _WorldsListPageState();
}

class _WorldsListPageState extends State<WorldsListPage> {
  final List<WorldCardSummary> _items = <WorldCardSummary>[];
  bool _loading = true;
  bool _failed = false;
  bool _noMore = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failed = false;
        _page = 1;
        _noMore = false;
      });
    }
    try {
      final Map<String, dynamic> data = await widget.loader(_page);
      final Object? raw = data['items'];
      final List<WorldCardSummary> got = raw is List
          ? raw
              .whereType<Map>()
              .map((Map e) =>
                  WorldCardSummary.fromJson(e.cast<String, dynamic>()))
              .where((WorldCardSummary w) => w.id.isNotEmpty)
              .toList()
          : <WorldCardSummary>[];
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(got);
        _noMore = data['has_next'] != true;
        _page += 1;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// 撤回（软删除）：二次确认，成功后原地刷新。
  Future<void> _withdraw(WorldCardSummary item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤回世界卡？'),
        content: Text(
          '「${item.name}」撤回后其他人就看不到了。已下载过的人不受影响。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final deleter = widget.deleter ?? ApiClient.instance.deleteWorld;
      await deleter(item.id);
      if (!mounted) return;
      _snack('已撤回');
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      _snack('撤回失败：$e');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && _items.isEmpty) {
      return ErrorState(
        message: '加载失败，请重试',
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.public_off_outlined,
        title: widget.emptyText,
      );
    }
    return LoadMoreListView(
      itemCount: _items.length,
      hasMore: !_noMore,
      onLoadMore: _load,
      onRefresh: () => _load(reset: true),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) =>
          _tile(context, _items[index]),
    );
  }

  Widget _tile(BuildContext context, WorldCardSummary item) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String statusLabel = widget.manageable ? item.statusLabel : '';
    final String when = formatRelativeTime(
      (item.updatedAt ?? item.createdAt)?.toIso8601String() ?? '',
    );
    final String meta = <String>[
      if (item.entryCount > 0) '${item.entryCount} 词条',
      if (item.sizeLabel.isNotEmpty) item.sizeLabel,
      if (item.copyCount > 0) '复制 ${item.copyCount}',
      if (when.isNotEmpty) when,
    ].join(' · ');

    return ListTile(
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (statusLabel.isNotEmpty) ...<Widget>[
            AppSpacing.hXs,
            WorldStatusChip(summary: item),
          ],
        ],
      ),
      trailing: widget.manageable
          ? PopupMenuButton<String>(
              onSelected: (String value) {
                if (value == 'open') _open(item);
                if (value == 'withdraw') _withdraw(item);
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'open', child: Text('查看详情')),
                PopupMenuItem<String>(value: 'withdraw', child: Text('撤回')),
              ],
            )
          : const Icon(Icons.chevron_right, size: 20),
      onTap: () => _open(item),
    );
  }

  void _open(WorldCardSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldDetailPage(
          id: item.id,
          fallbackName: item.name,
          importSink: widget.importSink,
        ),
      ),
    );
  }
}

/// 审核状态徽章（世界卡版）：列表页与作者主页共用。
///
/// 与「我的角色卡」的 StatusChip 同一个观感，但多两档：世界卡会「已下架」
/// 和「已撤回」—— 用角色卡那个两档的徽章会把它们都显示成「审核中」。
class WorldStatusChip extends StatelessWidget {
  const WorldStatusChip({super.key, required this.summary});

  final WorldCardSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (summary.status) {
      'approved' => summary.isHidden
          ? (cs.surfaceContainerHighest, cs.onSurfaceVariant)
          : (cs.primaryContainer, cs.onPrimaryContainer),
      'rejected' => (cs.errorContainer, cs.onErrorContainer),
      'deleted' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.tertiaryContainer, cs.onTertiaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        summary.statusLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
