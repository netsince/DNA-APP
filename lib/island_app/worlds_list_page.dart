import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_tag_suggestions.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/world_editor_page.dart';
import 'package:dna/services/world_export_import_service.dart';
import 'package:dna/theme/tokens.dart';

/// 世界卡的**通用列表页**：给「我的世界卡」「我收藏的世界卡」这类入口复用。
///
/// 和社区栏目里的 [WorldsBody] 的区别：那个是探索页形态（筛选 + 网格），是「逛」
/// 用的；这个只有一份数据 + 分页，是「看自己的」用的。
///
/// [manageable] 为 true 时（「我的世界卡」）每行额外显示审核状态徽章，并给出
/// 编辑 / 隐藏 / 重新提审 / 撤回 —— 与「我的角色卡」同一套管理动作。
class WorldsListPage extends StatefulWidget {
  const WorldsListPage({
    super.key,
    required this.title,
    required this.loader,
    this.emptyText = '这里还没有世界卡。',
    this.importSink,
    this.manageable = false,
    this.deleter,
    this.hider,
    this.resubmitter,
    this.sourceLoader,
    this.updater,
    this.editorOpener,
  });

  final String title;

  /// (page) -> 分页对象（items / has_next）。
  final Future<Map<String, dynamic>> Function(int page) loader;

  final String emptyText;

  /// 导入落地用的窄接口；为空时详情页不给导入按钮。
  final WorldImportSink? importSink;

  /// 是否是「我的世界卡」：显示状态徽章与管理动作。
  final bool manageable;

  /// 注入用：撤回 / 隐藏 / 重新提审 / 取原文 / 保存（测试替换为 stub）。
  final Future<void> Function(String id)? deleter;
  final Future<bool> Function(String id)? hider;
  final Future<void> Function(String id)? resubmitter;
  final Future<String> Function(String id)? sourceLoader;
  final Future<void> Function(String id, String raw)? updater;

  /// 注入用：打开编辑器（测试替换）。默认 push 完整世界观编辑器。
  final Future<void> Function(BuildContext context, World world, String worldId)?
      editorOpener;

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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 撤回（软删除）：二次确认，成功后原地刷新。
  Future<void> _withdraw(WorldCardSummary item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤回世界卡？'),
        content: Text('「${item.name}」撤回后其他人就看不到了。已下载过的人不受影响。'),
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
      _snack('撤回失败：$e');
    }
  }

  /// 下架 / 恢复（不动审核状态）。
  Future<void> _toggleHidden(WorldCardSummary item) async {
    try {
      final hider = widget.hider ?? ApiClient.instance.hideWorld;
      final bool hidden = await hider(item.id);
      if (!mounted) return;
      _snack(hidden ? '已下架，其他人看不到了' : '已恢复');
      await _load(reset: true);
    } catch (e) {
      _snack('操作失败：$e');
    }
  }

  /// 重新提审（被拒绝 / 已撤回的条目）。
  Future<void> _resubmit(WorldCardSummary item) async {
    try {
      final resubmitter = widget.resubmitter ?? ApiClient.instance.resubmitWorld;
      await resubmitter(item.id);
      if (!mounted) return;
      _snack('已重新提审，等待审核');
      await _load(reset: true);
    } catch (e) {
      _snack('重新提审失败：$e');
    }
  }

  /// 编辑：拉自己的原文 → 解析 → 打开完整编辑器 → 保存 = 整份替换并重新提审。
  ///
  /// 取原文走 /source（**不记复制统计**），不是 /export —— 作者改自己的东西
  /// 不该被算成别人复制了一次。
  Future<void> _edit(WorldCardSummary item) async {
    try {
      final source = widget.sourceLoader ?? ApiClient.instance.getWorldSource;
      final String text = await source(item.id);
      final ExportImportResult<World> parsed =
          WorldExportImportService.importWorld(text);
      final World? world = parsed.data;
      if (world == null) {
        _snack('这个世界的格式无法识别，暂时不能编辑');
        return;
      }
      if (!mounted) return;
      final opener = widget.editorOpener;
      if (opener != null) {
        await opener(context, world, item.id);
      } else {
        // 候选标签由社区页拉好传进去（编辑器本身不请求社区接口）。
        final List<String> suggestions = await loadWorldTagSuggestions();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorldEditorPage(
              world: world,
              title: '编辑世界卡',
              tagSuggestions: suggestions,
              saveLabel: '保存并重新提审',
              onSave: (World edited) => _save(item.id, edited),
            ),
          ),
        );
      }
      if (mounted) await _load(reset: true);
    } catch (e) {
      _snack('打开编辑器失败：$e');
    }
  }

  Future<void> _save(String id, World world) async {
    final updater = widget.updater ?? ApiClient.instance.updateWorld;
    // 发裸 World JSON：服务端只读顶层字段，套一层信封它就读不到了。
    await updater(id, jsonEncode(world.toJson()));
    if (mounted) _snack('已保存，正在等待重新审核');
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
                switch (value) {
                  case 'open':
                    _open(item);
                  case 'edit':
                    _edit(item);
                  case 'hidden':
                    _toggleHidden(item);
                  case 'resubmit':
                    _resubmit(item);
                  case 'withdraw':
                    _withdraw(item);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'open',
                  child: Text('查看详情'),
                ),
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('编辑'),
                ),
                if (item.status == 'approved')
                  PopupMenuItem<String>(
                    value: 'hidden',
                    child: Text(item.isHidden ? '取消下架' : '下架'),
                  ),
                if (item.status == 'rejected' || item.status == 'deleted')
                  const PopupMenuItem<String>(
                    value: 'resubmit',
                    child: Text('重新提审'),
                  ),
                if (item.status != 'deleted')
                  const PopupMenuItem<String>(
                    value: 'withdraw',
                    child: Text('撤回'),
                  ),
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
/// 和「已撤回」—— 用角色卡那个两档的徽章会把它们都显示成「待审核」。
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
