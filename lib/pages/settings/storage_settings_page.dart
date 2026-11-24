import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_content_frame.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'package:dna/widgets/state_views.dart';

import '../../services/attachment_gc.dart';
import '../../services/storage_usage_service.dart';
import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';

/// 「存储空间」设置页：先给一个总览（占用条 + 一句话），再给七类明细。
///
/// ## 为什么不是「扫一遍文档目录然后列出来」
///
/// 口径在 [StorageUsageService] 的文件头里；页面上只需要记住三件事：
/// 1. 数字**可能不全**（读库失败、磁盘容量拿不到），所以每一种「不全」都要
///    在界面上说出来 —— 静默显示一个偏小的数比报错更坏；
/// 2. 扫描是异步的，进页先出加载态，别让用户对着白屏等；
/// 3. 磁盘总量不是每台设备都拿得到，拿不到就写「未知」，只显示本应用占多少。
///
/// ## 两层页面
///
/// 第一层（本页）= 总览 + 七个分类；第二层（_StorageCategoryDetailPage）
/// = 某一类的明细，按大小排序，点任意一行就能看见「都下过什么」。
class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key, this.service, this.controller});

  /// 盘点服务。留空走真实实现；测试可以注入假数据源。
  final StorageUsageService? service;

  /// 用来算「哪些附件还被消息引用着」。
  ///
  /// 为空时（纯测试场景）不显示回收入口 —— 没有引用集合就没法判断谁是孤儿，
  /// 宁可不给按钮，也不做「猜着删」。
  final AppController? controller;

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late final StorageUsageService _service =
      widget.service ?? StorageUsageService();

  StorageUsageReport? _report;
  String? _error;
  bool _scanning = false;

  /// 当前没人引用的附件（删会话/回溯后留下的孤儿）。
  List<String> _orphans = const <String>[];
  int _orphanBytes = 0;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  /// 统计孤儿附件：**只统计，不删**。真正的删除要用户点按钮确认。
  ///
  /// 没有引用集合（未传 controller）时直接跳过 —— 没有判据就不给入口。
  Future<void> _scanOrphans() async {
    final AppController? controller = widget.controller;
    if (controller == null) return;
    try {
      final Set<String> liveRefs = liveAttachmentRefs(
        controller.allConversations,
      );
      final List<String> orphans = await AttachmentGc.findOrphans(
        liveRefs: liveRefs,
      );
      final int bytes = await AttachmentGc.orphanBytes(orphans);
      if (!mounted) return;
      setState(() {
        _orphans = orphans;
        _orphanBytes = bytes;
      });
    } catch (e) {
      // 统计失败不影响页面主体：孤儿回收是附加能力，不该把总览拖垮。
      debugPrint('[storage] 孤儿统计失败: $e');
    }
  }

  /// 回收孤儿附件（会二次确认）。
  Future<void> _cleanOrphans() async {
    if (_cleaning || _orphans.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const FitText('清理未引用的附件'),
        content: FitText(
          '有 ${_orphans.length} 个附件已经没有消息在引用了（${formatStorageBytes(_orphanBytes)}）。'
          '清理后无法恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const FitText('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final AppController? controller = widget.controller;
    if (controller == null) return;
    setState(() => _cleaning = true);
    try {
      final Set<String> liveRefs = liveAttachmentRefs(
        controller.allConversations,
      );
      final AttachmentGcResult result = await AttachmentGc.collect(
        liveRefs: liveRefs,
      );
      if (!mounted) return;
      setState(() => _cleaning = false);
      showSnack(
        context,
        '已清理 ${result.deleted} 个附件（${formatStorageBytes(result.bytesFreed)}）'
        '${result.partialsRemoved > 0 ? '，另清掉 ${result.partialsRemoved} 个临时文件' : ''}',
      );
      await _scan();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cleaning = false);
      showSnack(context, '清理失败：$e');
    }
  }

  /// 扫一遍。失败时把原因留在 [_error] 里，让页面显示「为什么」+「重试」。
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final StorageUsageReport report = await _service.scan();
      if (!mounted) return;
      setState(() {
        _report = report;
        _scanning = false;
      });
      await _scanOrphans();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _error = '$error';
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FitText('存储空间'),
        actions: <Widget>[
          if (_scanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: AppSize.iconCard,
                  height: AppSize.iconCard,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '刷新',
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final StorageUsageReport? report = _report;
    if (report == null) {
      if (_scanning) {
        return const AppLoadingState(message: '正在清点文件…');
      }
      return AppErrorState(
        message: _error == null ? '扫描失败' : '扫描失败：$_error',
        onRetry: _scan,
      );
    }
    return _buildReport(context, report);
  }

  Widget _buildReport(BuildContext context, StorageUsageReport report) {
    return AppContentFrame(
      maxWidth: AppSize.settingsMaxWidth,
      child: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          if (report.recordsError != null)
            _WarningBanner(text: report.recordsError!),
          _buildOverview(context, report),
          AppSpacing.hLg,
          _buildCategories(context, report),
        ],
      ),
    );
  }

  Widget _buildOverview(BuildContext context, StorageUsageReport report) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int kinds = report.categories
        .where((StorageCategoryUsage usage) => usage.bytes > 0)
        .length;
    return SettingSection(
      collapsible: false,
      icon: Icons.pie_chart_outline,
      title: '占用总览',
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            FitText(
              formatStorageBytes(report.totalBytes),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: AppWeight.medium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FitText(
              '$kinds 类',
              style: AppTextStyles.caption(theme).copyWith(color: cs.outline),
            ),
          ],
        ),
        AppSpacing.hMd,
        _UsageBar(report: report),
        if (_orphans.isNotEmpty) ...<Widget>[
          AppSpacing.hMd,
          _OrphanCleanupRow(
            count: _orphans.length,
            bytes: _orphanBytes,
            cleaning: _cleaning,
            onClean: _cleanOrphans,
          ),
        ],
        if (report.unreadableRecords > 0) ...<Widget>[
          AppSpacing.hSm,
          FitText(
            '有 ${report.unreadableRecords} 条数据读不出来，没算进明细。',
            style: AppTextStyles.caption(theme).copyWith(color: cs.error),
          ),
        ],
      ],
    );
  }

  Widget _buildCategories(BuildContext context, StorageUsageReport report) {
    return SettingSection(
      collapsible: false,
      icon: Icons.folder_outlined,
      title: '分类明细',
      children: <Widget>[
        for (final StorageCategoryUsage usage in report.categories)
          _CategoryRow(
            usage: usage,
            totalBytes: report.totalBytes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => _StorageCategoryDetailPage(
                  usage: usage,
                  appTotalBytes: report.totalBytes,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 顶部那条占用条：整条 = 本应用占用，按分类切段。
///
/// 段的颜色不是同色系深浅 —— 那样七段看起来就是一条颜色。这里从当前
/// ColorScheme 的 primary 出发按色相均分（莫奈取色跟着壁纸走），保证相邻段
/// 肉眼能区分。
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.report});

  final StorageUsageReport report;

  static const double _height = 18;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<StorageCategoryUsage> used = report.categories
        .where((StorageCategoryUsage usage) => usage.bytes > 0)
        .toList();
    return ClipRRect(
      borderRadius: AppRadius.xsAll,
      child: Container(
        key: const ValueKey<String>('storage_usage_bar'),
        height: _height,
        color: cs.surfaceContainerHighest,
        child: report.totalBytes == 0
            ? const SizedBox.shrink()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < used.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      flex: used[i].bytes,
                      child: ColoredBox(
                        key: ValueKey<String>(
                          'storage_usage_seg_${used[i].category.name}',
                        ),
                        color: storageCategoryColor(cs, used[i].category),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// 可回收附件：条形下面一行，够用就行，不另起一块 section。
class _OrphanCleanupRow extends StatelessWidget {
  const _OrphanCleanupRow({
    required this.count,
    required this.bytes,
    required this.cleaning,
    required this.onClean,
  });

  final int count;
  final int bytes;
  final bool cleaning;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.auto_delete_outlined, size: 18, color: cs.tertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FitText(
            '可回收 $count 个附件 · ${formatStorageBytes(bytes)}',
            style: AppTextStyles.body(theme),
          ),
        ),
        TextButton(
          onPressed: cleaning ? null : onClean,
          child: FitText(cleaning ? '清理中…' : '清理'),
        ),
      ],
    );
  }
}

/// 分类行：色点 + 名称 + 项数 / 右侧占比与大小，点进去看明细。
///
/// 色点与占用条上的一段同色，用户扫一眼就能把「条上这块」和「列表这行」对上。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.usage,
    required this.totalBytes,
    required this.onTap,
  });

  final StorageCategoryUsage usage;
  final int totalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color color = storageCategoryColor(cs, usage.category);
    final bool empty = usage.itemCount == 0;
    final TextStyle? valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: AppWeight.medium,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !empty,
      onTap: empty ? null : onTap,
      leading: SizedBox(
        width: 24,
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: empty ? cs.outlineVariant : color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      title: FitText(storageCategoryLabel(usage.category)),
      subtitle: FitText(
        empty ? '暂无' : '${usage.itemCount} 项',
        style: AppTextStyles.caption(theme).copyWith(color: cs.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FitText(
                empty ? '—' : _percent(usage.bytes, totalBytes),
                style: valueStyle,
              ),
              FitText(
                formatStorageBytes(usage.bytes),
                style: AppTextStyles.caption(theme).copyWith(color: cs.outline),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: cs.outline),
        ],
      ),
    );
  }
}

/// 第二层：某一类的明细。默认按大小降序（服务端已排好），可切到按名称。
class _StorageCategoryDetailPage extends StatefulWidget {
  const _StorageCategoryDetailPage({
    required this.usage,
    required this.appTotalBytes,
  });

  final StorageCategoryUsage usage;

  /// 本应用总占用（页头用来说明「这一类占了多少」）。
  final int appTotalBytes;

  @override
  State<_StorageCategoryDetailPage> createState() =>
      _StorageCategoryDetailPageState();
}

class _StorageCategoryDetailPageState
    extends State<_StorageCategoryDetailPage> {
  bool _byName = false;

  List<StorageUsageItem> get _items {
    final List<StorageUsageItem> items = <StorageUsageItem>[
      ...widget.usage.items,
    ];
    if (_byName) {
      items.sort(
        (StorageUsageItem a, StorageUsageItem b) => a.name.compareTo(b.name),
      );
    }
    // 默认顺序即服务给出的「按大小降序」，不用再排一次。
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final StorageCategoryUsage usage = widget.usage;
    final List<StorageUsageItem> items = _items;

    return Scaffold(
      appBar: AppBar(
        title: FitText(storageCategoryLabel(usage.category)),
        actions: <Widget>[
          IconButton(
            tooltip: _byName ? '按大小排序' : '按名称排序',
            onPressed: () => setState(() => _byName = !_byName),
            icon: Icon(_byName ? Icons.sort_by_alpha : Icons.sort),
          ),
        ],
      ),
      body: items.isEmpty
          ? const AppEmptyState(
              icon: Icons.folder_off_outlined,
              title: '这一类还是空的',
            )
          : AppContentFrame(
              maxWidth: AppSize.settingsMaxWidth,
              child: ListView(
                padding: AppInsets.page,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      FitText(
                        formatStorageBytes(usage.bytes),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FitText(
                        '${usage.itemCount} 项 · 占全部 '
                        '${_percent(usage.bytes, widget.appTotalBytes)}',
                        style: AppTextStyles.caption(
                          theme,
                        ).copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                  if (usage.truncated) ...<Widget>[
                    AppSpacing.hXs,
                    FitText(
                      '只列出最大的 ${usage.items.length} 项，其余 '
                      '${usage.itemCount - usage.items.length} 项没显示。',
                      style: AppTextStyles.caption(
                        theme,
                      ).copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  AppSpacing.hMd,
                  for (final StorageUsageItem item in items)
                    _DetailRow(item: item, categoryBytes: usage.bytes),
                ],
              ),
            ),
    );
  }
}

/// 明细里的一行：名称 + 说明 + 大小。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.item, required this.categoryBytes});

  final StorageUsageItem item;

  /// 所属分类的总字节数（算「占这一类的百分之几」）。
  final int categoryBytes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> subtitleParts = <String>[
      if (item.note != null && item.note!.isNotEmpty) item.note!,
      '占 ${_percent(item.bytes, categoryBytes)}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: FitText(item.name),
      subtitle: FitText(
        subtitleParts.join(' · '),
        style: AppTextStyles.caption(
          theme,
        ).copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: FitText(
        formatStorageBytes(item.bytes),
        style: AppTextStyles.body(theme).copyWith(fontWeight: AppWeight.medium),
      ),
    );
  }
}

/// 读库失败/数据不全时的提示条。
///
/// 用 error 色而不是普通说明：这一条意味着**上面的数字不全**，
/// 用户有权知道。
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.lg,
      ),
      child: Container(
        padding: AppInsets.card,
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, size: AppSize.iconCard, color: cs.error),
            AppSpacing.wSm,
            Expanded(
              child: FitText(
                '$text。下面的数字可能不全，点右上角刷新重试。',
                style: AppTextStyles.caption(
                  theme,
                ).copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类颜色：从 primary 渐变到 tertiary，七个分类各一档。
///
/// 不引入调色板常量（项目禁止硬编码颜色），也不用七种无关色相 ——
/// 色阶顺序即分类顺序，和上面列表的行序对得上。
/// 每个分类一个颜色：从当前主题的主色出发，按色相均分取七种色系。
///
/// 不用「同色相深浅」——那七段看起来就是一条颜色；也不直接用满饱和度的
/// 原色，那样像荧光彩虹。这里压低饱和度、把亮度拉齐，得到一组柔和的七色。
Color storageCategoryColor(ColorScheme cs, StorageCategory category) {
  final HSLColor base = HSLColor.fromColor(cs.primary);
  final int total = StorageCategory.values.length;
  final double hue = (base.hue + category.index * 360 / total) % 360;
  return HSLColor.fromAHSL(1, hue, 0.42, 0.55).toColor();
}

/// 占比文字。整数位够用时不留小数，太小的小数写成「<0.1%」。
String _percent(int part, int total) {
  if (total <= 0 || part <= 0) return '0%';
  final double percent = part / total * 100;
  if (percent >= 10) return '${percent.toStringAsFixed(0)}%';
  if (percent >= 0.1) return '${percent.toStringAsFixed(1)}%';
  return '<0.1%';
}
