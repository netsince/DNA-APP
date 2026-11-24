import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/widgets/paged_list_body.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/status_badge.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_tag_suggestions.dart';
import 'package:dna/models/world.dart';
import 'package:dna/island_app/world_publish_page.dart';
import 'package:dna/services/world_export_import_service.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/utils/action_table.dart';

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
  final Future<void> Function(
    BuildContext context,
    World world,
    String worldId,
  )?
  editorOpener;

  @override
  State<WorldsListPage> createState() => _WorldsListPageState();
}

class _WorldsListPageState extends State<WorldsListPage> {
  /// 分页状态（加载中 / 没有更多 / 页码 / 失败）统一由 [PagedController] 管，
  /// 页面只提供「怎么取一页」。页码从 1 开始（与接口一致）。
  late final PagedController<WorldCardSummary> _paged =
      PagedController<WorldCardSummary>(
        fetch: (int page) async {
          final Map<String, dynamic> data = await widget.loader(page);
          final Object? raw = data['items'];
          final List<WorldCardSummary> items = raw is List
              ? raw
                    .whereType<Map>()
                    .map(
                      (Map e) =>
                          WorldCardSummary.fromJson(e.cast<String, dynamic>()),
                    )
                    .where((WorldCardSummary w) => w.id.isNotEmpty)
                    .toList()
              : <WorldCardSummary>[];
          return PagedResult<WorldCardSummary>(
            items: items,
            hasMore: data['has_next'] == true,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        // 首屏失败才显示错误文案；翻页失败保留已加载内容（控制器保证）。
        firstLoadError: '加载失败，请重试',
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

  void _snack(String text) {
    if (!mounted) return;
    showSnack(context, text);
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
      await _paged.refresh();
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
      await _paged.refresh();
    } catch (e) {
      _snack('操作失败：$e');
    }
  }

  /// 重新提审（被拒绝 / 已撤回的条目）。
  Future<void> _resubmit(WorldCardSummary item) async {
    try {
      final resubmitter =
          widget.resubmitter ?? ApiClient.instance.resubmitWorld;
      await resubmitter(item.id);
      if (!mounted) return;
      _snack('已重新提审，等待审核');
      await _paged.refresh();
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
            builder: (_) => CommunityWorldEditorPage(
              world: world,
              title: '编辑世界卡',
              tagSuggestions: suggestions,
              saveLabel: '保存并重新提审',
              onSave: (World edited) => _save(item.id, edited),
            ),
          ),
        );
      }
      if (mounted) await _paged.refresh();
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
      // 五态 + 下拉刷新 + 触底加载由 [PagedListBody] 统一负责；本页只给
      // 「一行怎么画」（行菜单已经是动作表，见 [_tile]）。空态文案仍由
      // [emptyText] 注入。
      body: PagedListBody<WorldCardSummary>(
        controller: _paged,
        separator: (_, _) => const Divider(height: 1),
        empty: EmptyState(
          icon: Icons.public_off_outlined,
          title: widget.emptyText,
        ),
        itemBuilder: (BuildContext context, int index) =>
            _tile(context, _paged.items[index]),
      ),
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

    // 逐行动作表：可见项随审核状态 / 下架状态变（文案与图标与原来逐字一致）。
    final List<RowAction> actions = <RowAction>[
      RowAction(id: 'open', label: '查看详情', onSelected: () => _open(item)),
      RowAction(id: 'edit', label: '编辑', onSelected: () => _edit(item)),
      // 下架 / 取消下架：只有已通过的世界卡才有（服务端同样校验）。
      RowAction(
        id: 'hidden',
        label: item.isHidden ? '取消下架' : '下架',
        visible: item.status == 'approved',
        onSelected: () => _toggleHidden(item),
      ),
      // 重新提审：被拒绝或已撤回的条目。
      RowAction(
        id: 'resubmit',
        label: '重新提审',
        visible: item.status == 'rejected' || item.status == 'deleted',
        onSelected: () => _resubmit(item),
      ),
      // 撤回：已撤回的条目不再给这个动作。
      RowAction(
        id: 'withdraw',
        label: '撤回',
        visible: item.status != 'deleted',
        onSelected: () => _withdraw(item),
      ),
    ];

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
      // 行内菜单由动作表渲染：可见项随状态变，页面只说「有哪些动作」。
      trailing: widget.manageable && hasVisibleRowAction(actions)
          ? rowActionMenu(
              actions: actions,
              // 原实现未传 tooltip（= Material 的本地化默认），这里传入同一取值，
              // 免得换成共享层默认的「更多操作」。
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
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
/// 世界卡比角色卡多两档（会「已下架」「已撤回」），所以这里只负责把
/// status 映射成 [StatusBadge] 的色档 + 图标 —— 视觉（色对 / 字号 / 圆角 /
/// 无 ink）只有 StatusBadge 一份实现，这是第六套自绘标签的收口点（审计 5 节）。
class WorldStatusChip extends StatelessWidget {
  const WorldStatusChip({super.key, required this.summary});

  final WorldCardSummary summary;

  @override
  Widget build(BuildContext context) {
    // 状态 → (色调, 图标) 的映射只有一份：[worldStatusStyle]。
    final ({BadgeTone tone, IconData icon}) style = worldStatusStyle(
      status: summary.status,
      hidden: summary.isHidden,
    );
    return StatusBadge(
      label: summary.statusLabel,
      icon: style.icon,
      tone: style.tone,
      semanticLabel: '审核状态：${summary.statusLabel}',
    );
  }
}
