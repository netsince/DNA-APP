import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'package:dna/widgets/state_views.dart';

import '../../services/storage_usage_service.dart';

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
  const StorageSettingsPage({super.key, this.service});

  /// 盘点服务。留空走真实实现；测试可以注入假数据源。
  final StorageUsageService? service;

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late final StorageUsageService _service =
      widget.service ?? StorageUsageService();

  StorageUsageReport? _report;
  String? _error;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
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
    return ListView(
      padding: AppInsets.page,
      children: <Widget>[
        if (report.recordsError != null)
          _WarningBanner(text: report.recordsError!),
        _buildOverview(context, report),
        _buildCategories(context, report),
      ],
    );
  }

  Widget _buildOverview(BuildContext context, StorageUsageReport report) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return SettingSection(
      icon: Icons.donut_small_outlined,
      title: '占用总览',
      description: report.filesScanned
          ? '本应用自己占了多大一块，以及都去哪儿了。'
          : '网页版读不到本地目录，这里只统计浏览器里存的数据。',
      children: <Widget>[
        _UsageBar(report: report),
        AppSpacing.hMd,
        FitText(_compositionLine(report), style: AppTextStyles.body(theme)),
        AppSpacing.hXs,
        FitText(
          _diskLine(report),
          style: AppTextStyles.caption(
            theme,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
        if (report.unreadableRecords > 0) ...<Widget>[
          AppSpacing.hSm,
          SettingHint(
            '有 ${report.unreadableRecords} 条数据读不出来（内容可能坏了），没算进明细里。',
            icon: Icons.report_gmailerrorred_outlined,
            color: cs.error,
          ),
        ],
        AppSpacing.hSm,
        FitText(
          _scannedAtLine(report),
          style: AppTextStyles.tiny(theme).copyWith(color: cs.outline),
        ),
      ],
    );
  }

  Widget _buildCategories(BuildContext context, StorageUsageReport report) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SettingSection(
      icon: Icons.folder_outlined,
      title: '分类明细',
      description: '点任意一类，看看这些空间都被谁占了。',
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
        AppSpacing.hSm,
        SettingHint(
          '只算本应用自己写进「文档」目录的东西；你放在那里的其它文件不算在内。',
          icon: Icons.info_outline,
          color: cs.outline,
        ),
      ],
    );
  }

  /// 「共占用 X，其中 ……」—— 分类列表的一行话版。
  String _compositionLine(StorageUsageReport report) {
    final List<StorageCategoryUsage> nonEmpty = report.categories
        .where((StorageCategoryUsage usage) => usage.bytes > 0)
        .toList()
      ..sort(
        (StorageCategoryUsage a, StorageCategoryUsage b) =>
            b.bytes.compareTo(a.bytes),
      );
    if (nonEmpty.isEmpty) {
      return '共占用 0 B，还没有存下任何东西。';
    }
    final String top = nonEmpty
        .take(3)
        .map(
          (StorageCategoryUsage usage) =>
              '${storageCategoryLabel(usage.category)} '
              '${formatStorageBytes(usage.bytes)}',
        )
        .join('、');
    final String tail = nonEmpty.length > 3 ? ' 等 ${nonEmpty.length} 类' : '';
    return '共占用 ${formatStorageBytes(report.totalBytes)}，其中 $top$tail';
  }

  /// 磁盘那一行。拿不到就明说「未知」，绝不按已用 × 系数倒推总量。
  String _diskLine(StorageUsageReport report) {
    if (!report.filesScanned) {
      return '磁盘总量：未知（浏览器里拿不到）。';
    }
    final StorageDiskSpace? disk = report.disk;
    final int? used = disk?.usedBytes;
    if (disk != null && disk.hasTotal && used != null) {
      final String label = disk.label ?? '磁盘';
      return '$label 已用 ${formatStorageBytes(used)} / 共 '
          '${formatStorageBytes(disk.totalBytes!)}'
          '（${_percent(used, disk.totalBytes!)}）· '
          '剩余 ${formatStorageBytes(disk.freeBytes!)} · '
          '本应用占 ${_percent(report.totalBytes, disk.totalBytes!)}';
    }
    return '磁盘总量：未知（这个平台拿不到），只能显示本应用占了多少。';
  }

  String _scannedAtLine(StorageUsageReport report) {
    final DateTime at = report.scannedAt;
    String two(int value) => value.toString().padLeft(2, '0');
    return '清点时间 ${two(at.hour)}:${two(at.minute)} · '
        '数据有变化就点右上角刷新';
  }
}

/// 顶部那条占用条。
///
/// * 拿得到磁盘总量：整条 = 磁盘，左边填满的部分 = 本应用（再按分类切段）；
/// * 拿不到：整条 = 本应用自己的构成（「仅已用」）。
///
/// 本应用占比极小时按最小 3 像素画 —— 否则条形看不见，用户会以为没数据；
/// 具体百分比一律以文字为准。
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.report});

  final StorageUsageReport report;

  /// 占用条高度（[AppSpacing.md]，与页面其它细条的视觉重量一致）。
  static const double _height = AppSpacing.md;

  /// 应用占用极小时的最小可见宽度。
  static const double _minFilledWidth = 3;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final StorageDiskSpace? disk = report.disk;
    final int? diskTotal = (disk != null && disk.hasTotal)
        ? disk.totalBytes
        : null;
    final double share = diskTotal == null
        ? 1
        : (report.totalBytes / diskTotal).clamp(0.0, 1.0);
    final List<StorageCategoryUsage> used = report.categories
        .where((StorageCategoryUsage usage) => usage.bytes > 0)
        .toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double filled = report.totalBytes == 0
            ? 0
            : (width * share).clamp(_minFilledWidth, width);
        return ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: SizedBox(
            height: _height,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(color: cs.surfaceContainerHighest),
                ),
                if (filled > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: filled,
                    child: Row(
                      children: <Widget>[
                        for (final StorageCategoryUsage usage in used)
                          Expanded(
                            flex: usage.bytes,
                            child: ColoredBox(
                              color: _categoryColor(cs, usage.category),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 分类行：图标 + 名称 + 大小 + 占比，点进去看明细。
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
    final Color color = _categoryColor(cs, usage.category);
    final bool empty = usage.itemCount == 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !empty,
      onTap: empty ? null : onTap,
      leading: Container(
        width: AppSize.iconBox,
        height: AppSize.iconBox,
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppAlpha.a12),
          borderRadius: AppRadius.xsAll,
        ),
        child: Icon(
          _categoryIcon(usage.category),
          size: AppSize.iconCard,
          color: color,
        ),
      ),
      title: FitText(storageCategoryLabel(usage.category)),
      subtitle: FitText(
        empty
            ? '暂无'
            : '共 ${usage.itemCount} 项 · 占 '
                  '${_percent(usage.bytes, totalBytes)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FitText(
            formatStorageBytes(usage.bytes),
            style: AppTextStyles.body(
              theme,
            ).copyWith(fontWeight: AppWeight.medium),
          ),
          const Icon(Icons.chevron_right),
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
              title: '这一类还没有东西',
              description: '等有了内容再回来看。',
            )
          : ListView(
              padding: AppInsets.page,
              children: <Widget>[
                FitText(
                  '共 ${usage.itemCount} 项 · '
                  '${formatStorageBytes(usage.bytes)}'
                  ' · 占全部 ${_percent(usage.bytes, widget.appTotalBytes)}',
                  style: AppTextStyles.body(theme),
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
                '$text。下面这些分类可能不全，点右上角刷新可以重试。',
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
Color _categoryColor(ColorScheme cs, StorageCategory category) {
  final int last = StorageCategory.values.length - 1;
  final double t = last <= 0 ? 0 : (category.index / last) * 0.85;
  return Color.lerp(cs.primary, cs.tertiary, t) ?? cs.primary;
}

/// 分类图标。
IconData _categoryIcon(StorageCategory category) => switch (category) {
  StorageCategory.conversations => Icons.forum_outlined,
  StorageCategory.characters => Icons.person_outline,
  StorageCategory.worlds => Icons.public_outlined,
  StorageCategory.cache => Icons.bolt_outlined,
  StorageCategory.downloads => Icons.cloud_download_outlined,
  StorageCategory.attachments => Icons.attach_file,
  StorageCategory.other => Icons.more_horiz,
};

/// 占比文字。整数位够用时不留小数，太小的小数写成「<0.1%」。
String _percent(int part, int total) {
  if (total <= 0 || part <= 0) return '0%';
  final double percent = part / total * 100;
  if (percent >= 10) return '${percent.toStringAsFixed(0)}%';
  if (percent >= 0.1) return '${percent.toStringAsFixed(1)}%';
  return '<0.1%';
}
