import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/report_sheet.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_tag_suggestions.dart';
import 'package:dna/models/world.dart';
import 'package:dna/island_app/world_publish_page.dart';
import 'package:dna/services/world_export_import_service.dart';
import 'package:dna/theme/tokens.dart';

/// 世界卡详情：元信息 + 词条索引（分组 / 搜索 / 折叠）+ 1 条示例 + 「导入到我的世界」。
///
/// **刻意不给全文**：全展示就没人愿意发布（别人抄走就行），全不展示就没人
/// 愿意导入（不知道里面写了什么）。所以给词条名、类型、触发词和一条示例，
/// 够判断要不要。
///
/// 正文只在点「导入」时才取 —— 那一次请求同时被服务端记成一次「复制」。
class WorldDetailPage extends StatefulWidget {
  const WorldDetailPage({
    super.key,
    required this.id,
    this.fallbackName = '',
    this.importSink,
    this.detailLoader,
    this.textDownloader,
    this.reasonsLoader,
    this.reportSubmitter,
    this.favoriteToggler,
    this.clipboardWriter,
  });

  final String id;

  /// 详情还没加载出来时先用列表里已有的名字占位，避免标题闪一下。
  final String fallbackName;

  /// 导入落地用的窄接口。为空时不给导入按钮。
  final WorldImportSink? importSink;

  /// 详情加载器 / 原文下载器。为空时走 [ApiClient]；测试注入假数据。
  final Future<Map<String, dynamic>> Function(String id)? detailLoader;
  final Future<String> Function(String id)? textDownloader;

  /// 举报原因加载 / 提交回调；为空时走 [ApiClient]。**形参必须与
  /// [ApiClient.submitReport] 一致（都用命名参数）** —— 两者不一致时
  /// `widget.reportSubmitter ?? ApiClient.instance.submitReport` 这种写法会
  /// 在运行时炸，举报就这么坏过一次（见 card_detail_page 的同名注释）。
  final Future<List<({String key, String label})>> Function()? reasonsLoader;
  final Future<void> Function({
    required String type,
    required String id,
    required String reason,
    String? detail,
  })?
  reportSubmitter;

  /// 收藏 toggle 回调；为空时走 [ApiClient.favoriteWorld]。
  final Future<Map<String, dynamic>> Function(String id)? favoriteToggler;

  /// 剪贴板写入（测试注入；为空走系统剪贴板）。
  final Future<void> Function(String text)? clipboardWriter;

  @override
  State<WorldDetailPage> createState() => _WorldDetailPageState();
}

class _WorldDetailPageState extends State<WorldDetailPage> {
  WorldCardSummary? _detail;
  bool _loading = true;
  bool _importing = false;
  bool _favoriting = false;
  bool _favorited = false;
  int _favoriteCount = 0;
  String? _error;

  /// 词条本地过滤词（名字 / 触发词）。
  final TextEditingController _entryFilter = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entryFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final WorldCardSummary parsed = await _fetchDetail();
      if (!mounted) return;
      setState(() {
        _detail = parsed;
        _favorited = parsed.favorited;
        _favoriteCount = parsed.favoriteCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '详情加载失败，稍后重试';
        _loading = false;
      });
    }
  }

  Future<WorldCardSummary> _fetchDetail() async {
    final Future<Map<String, dynamic>> Function(String)? loader =
        widget.detailLoader;
    final Map<String, dynamic> data = loader != null
        ? await loader(widget.id)
        : await ApiClient.instance.getWorldDetail(widget.id);
    return WorldCardSummary.fromJson(data);
  }

  /// 静默刷新：导入之后复制量会 +1，但不该为此把整页打回转圈状态。
  Future<void> _refreshQuiet() async {
    try {
      final WorldCardSummary parsed = await _fetchDetail();
      if (!mounted) return;
      setState(() {
        _detail = parsed;
        _favorited = parsed.favorited;
        _favoriteCount = parsed.favoriteCount;
      });
    } catch (_) {
      // 刷新失败无所谓：页面上的旧数字仍然是对的（只是少了一次复制）。
    }
  }

  Future<void> _import() async {
    final WorldImportSink? sink = widget.importSink;
    if (sink == null || _importing) return;
    setState(() => _importing = true);
    try {
      // 1) 取原文（服务端在这一步记一次「复制」）。
      final Future<String> Function(String)? fetch = widget.textDownloader;
      final String text = fetch != null
          ? await fetch(widget.id)
          : await ApiClient.instance.downloadWorldText(widget.id);
      // 2) 解析。兼容三种格式：本应用带标识格式 / 裸 World JSON / 第三方世界书。
      final ExportImportResult<World> parsed =
          WorldExportImportService.importWorld(text);
      final World? world = parsed.data;
      if (world == null) {
        throw Exception(
          (parsed.message ?? '').isEmpty ? '世界格式无法识别' : parsed.message,
        );
      }
      // 3) 落盘。重新生成 id 由实现方负责（本地 id 与社区 id 是两套）。
      await sink.importWorld(world);
      if (!mounted) return;
      // 告诉用户导入了多少内容 —— 只说「已导入」，用户还得自己回去找。
      final int count = world.entries.length;
      _toast(count > 0 ? '已导入到「我的世界」：$count 个词条' : '已导入到「我的世界」');
      await _refreshQuiet();
    } catch (e) {
      if (!mounted) return;
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 收藏 / 取消收藏。
  Future<void> _toggleFavorite() async {
    if (!AuthGuard.isLoggedIn) {
      AuthGuard.require(context, message: '请先登录后再收藏');
      return;
    }
    setState(() => _favoriting = true);
    try {
      final Future<Map<String, dynamic>> Function(String)? toggle =
          widget.favoriteToggler;
      final Map<String, dynamic> result = toggle != null
          ? await toggle(widget.id)
          : await ApiClient.instance.favoriteWorld(widget.id);
      if (!mounted) return;
      setState(() {
        _favorited = result['favorited'] == true;
        final Object? count = result['count'];
        if (count is num) _favoriteCount = count.toInt();
      });
    } catch (_) {
      if (mounted) _toast('操作失败，请重试');
    } finally {
      if (mounted) setState(() => _favoriting = false);
    }
  }

  /// 复制网页版链接（`<服务器>/worlds/<id>`，无需登录即可打开）。
  Future<void> _copyLink() async {
    final String url = ServerConfig.resolveUrl('/worlds/${widget.id}');
    if (url.isEmpty) {
      _toast('尚未配置服务器地址');
      return;
    }
    try {
      final writer =
          widget.clipboardWriter ??
          (String text) => Clipboard.setData(ClipboardData(text: text));
      await writer(url);
      if (mounted) _toast('已复制网页链接');
    } catch (_) {
      if (mounted) _toast('复制失败，请重试');
    }
  }

  /// 举报入口：需登录，弹底部表单选择原因并提交。
  Future<void> _openReport() async {
    if (!AuthGuard.isLoggedIn) {
      AuthGuard.require(context, message: '请先登录后再举报');
      return;
    }
    // 拉取举报原因（失败则用内置兜底，别让举报这条路因为一个请求挂掉）。
    List<({String key, String label})> reasons;
    try {
      reasons =
          await (widget.reasonsLoader ?? ApiClient.instance.getReportReasons)();
    } catch (_) {
      reasons = const <({String key, String label})>[
        (key: 'spam', label: '垃圾广告 / 刷屏'),
        (key: 'porn', label: '色情低俗'),
        (key: 'violence', label: '暴力血腥'),
        (key: 'politics', label: '违规政治内容'),
        (key: 'abuse', label: '人身攻击 / 辱骂'),
        (key: 'copyright', label: '侵犯版权'),
        (key: 'other', label: '其他'),
      ];
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<({String key, String detail})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportSheet(
        title: '举报世界卡',
        reasons: reasons,
        onSubmitted: (key, detail) =>
            Navigator.of(context).pop((key: key, detail: detail)),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      final submit = widget.reportSubmitter ?? ApiClient.instance.submitReport;
      await submit(
        type: 'world',
        id: widget.id,
        reason: picked.key,
        detail: picked.detail,
      );
      if (!mounted) return;
      _toast('举报已提交，管理员会尽快处理');
    } catch (_) {
      if (!mounted) return;
      _toast('举报提交失败，请重试');
    }
  }

  /// 当前登录用户是否就是作者（只有作者能编辑）。
  bool get _isMine {
    final String me = (AuthSession.instance.user?['username'] ?? '').toString();
    final String author = _detail?.authorUsername ?? '';
    return me.isNotEmpty && me == author;
  }

  /// 编辑：拉自己的原文（**不记复制**）→ 解析 → 完整编辑器 → 保存 = 整份替换并重新提审。
  Future<void> _edit() async {
    final WorldCardSummary? d = _detail;
    if (d == null) return;
    try {
      final String text = await ApiClient.instance.getWorldSource(d.id);
      final ExportImportResult<World> parsed =
          WorldExportImportService.importWorld(text);
      final World? world = parsed.data;
      if (world == null) {
        _toast('这个世界的格式无法识别，暂时不能编辑');
        return;
      }
      if (!mounted) return;
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
            onSave: (World edited) async {
              await ApiClient.instance.updateWorld(
                d.id,
                jsonEncode(edited.toJson()),
              );
            },
          ),
        ),
      );
      if (mounted) await _load();
    } catch (e) {
      _toast('打开编辑器失败：$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _detail?.name.isNotEmpty == true
              ? _detail!.name
              : (widget.fallbackName.isNotEmpty ? widget.fallbackName : '世界卡'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _favorited ? '取消收藏' : '收藏',
            icon: Icon(_favorited ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _favoriting ? null : _toggleFavorite,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (String value) {
              if (value == 'link') _copyLink();
              if (value == 'report') _openReport();
              if (value == 'edit') _edit();
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              if (_isMine)
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined, size: 20),
                    title: Text('编辑'),
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'link',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link, size: 20),
                  title: Text('复制链接'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.flag_outlined, size: 20),
                  title: Text('举报'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: _detail == null ? null : _bottomBar(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error ?? '世界卡不存在'),
            AppSpacing.hMd,
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final WorldCardSummary d = _detail!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> meta = <String>[
      if (d.entryCount > 0) '${d.entryCount} 词条',
      if (d.sizeLabel.isNotEmpty) d.sizeLabel,
      if (d.viewCount > 0) '${d.viewCount} 次浏览',
      if (_favoriteCount > 0) '收藏 $_favoriteCount',
      if (d.copyCount > 0) '被复制 ${d.copyCount} 次',
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        _headCard(context, d, meta),
        AppSpacing.hLg,
        ..._entriesSection(context, d),
        if (d.sampleEntry != null) ...<Widget>[
          AppSpacing.hLg,
          _sectionTitle(context, '示例词条'),
          AppSpacing.hXs,
          Text(
            '其余词条只给名字与触发词，正文在导入后可见',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          AppSpacing.hSm,
          _sampleCard(context, d.sampleEntry!),
        ],
        AppSpacing.hXl,
      ],
    );
  }

  /// 资料卡头部：状态 / 名称 / 统计 / 简介 / 标签 / 作者。
  ///
  /// 详情页此前是一屏文章式排版，读起来像公告；世界书是**可以下载使用的资料**，
  /// 头部应该先给身份与统计，再往下才是目录。
  Widget _headCard(
    BuildContext context,
    WorldCardSummary d,
    List<String> meta,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (d.statusLabel.isNotEmpty) ...<Widget>[
            _statusBanner(context, d),
            AppSpacing.hMd,
          ],
          Text(
            d.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: AppWeight.medium,
            ),
          ),
          if (meta.isNotEmpty) ...<Widget>[
            AppSpacing.hXs,
            Text(
              meta.join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (d.summary.isNotEmpty) ...<Widget>[
            AppSpacing.hSm,
            Text(d.summary, style: theme.textTheme.bodyMedium),
          ],
          if (d.tags.isNotEmpty) ...<Widget>[
            AppSpacing.hSm,
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final String tag in d.tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          if (d.authorName.isNotEmpty || d.updatedAt != null) ...<Widget>[
            AppSpacing.hSm,
            _authorRow(context, d),
          ],
        ],
      ),
    );
  }

  /// 作者行：头像 + 昵称（可点进主页）+ 更新时间。
  Widget _authorRow(BuildContext context, WorldCardSummary d) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool tappable = d.authorUsername.isNotEmpty;
    return InkWell(
      borderRadius: AppRadius.smAll,
      onTap: tappable
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UserProfilePage(username: d.authorUsername),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            Avatar(avatar: d.authorAvatar, radius: 12),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                d.authorName.isEmpty ? '匿名' : d.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tappable ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (d.updatedAt != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '更新于 ${formatRelativeTime(d.updatedAt!.toIso8601String())}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (tappable) ...<Widget>[
              const SizedBox(width: AppSpacing.xxs),
              Icon(Icons.chevron_right, size: 16, color: cs.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }

  /// 审核 / 下架提示（只有作者自己会看到非 approved 的条目）。
  Widget _statusBanner(BuildContext context, WorldCardSummary d) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool pending = d.status == 'pending';
    final bool rejected = d.status == 'rejected';
    final Color bg = rejected ? cs.errorContainer : cs.tertiaryContainer;
    final Color fg = rejected ? cs.onErrorContainer : cs.onTertiaryContainer;
    final String text = pending
        ? '这个世界卡还在审核中，目前只有你自己能看到'
        : rejected
        ? '这个世界卡未通过审核，其他人看不到'
        : '这个世界卡已被下架，其他人看不到';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.smAll),
      child: Row(
        children: <Widget>[
          Icon(
            pending ? Icons.hourglass_empty : Icons.visibility_off_outlined,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFontSize.caption, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 词条：按人物 / 名词分组 + 本地搜索 + 折叠
  // ---------------------------------------------------------------------

  List<Widget> _entriesSection(BuildContext context, WorldCardSummary d) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<WorldEntryPreview> index = d.entryIndex;
    final bool legacy = index.isEmpty && d.entryNames.isNotEmpty;

    if (index.isEmpty && !legacy) {
      return <Widget>[
        _sectionTitle(context, '包含的词条'),
        AppSpacing.hXs,
        Text(
          '这个世界没有词条，或者词条名全部为空',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ];
    }

    if (legacy) {
      // 老服务端只给 entry_names：照样展示，只是没有分组和触发词。
      return <Widget>[
        _sectionTitle(context, '包含的词条'),
        AppSpacing.hXs,
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final String name in d.entryNames)
              _entryChip(context, name, const <String>[]),
          ],
        ),
      ];
    }

    final String filter = _filter.trim().toLowerCase();
    final List<WorldEntryPreview> hits = filter.isEmpty
        ? index
        : index
              .where((WorldEntryPreview e) => e.searchText.contains(filter))
              .toList();
    final List<WorldEntryPreview> people = hits
        .where((WorldEntryPreview e) => e.isPerson)
        .toList();
    final List<WorldEntryPreview> nouns = hits
        .where((WorldEntryPreview e) => !e.isPerson)
        .toList();

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: _sectionTitle(context, '包含的词条')),
          Text(
            filter.isEmpty ? '共 ${index.length} 条' : '命中 ${hits.length} 条',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      AppSpacing.hXs,
      TextField(
        controller: _entryFilter,
        onChanged: (String value) => setState(() => _filter = value),
        decoration: InputDecoration(
          hintText: '搜索词条名 / 触发词',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _entryFilter.clear();
                    setState(() => _filter = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: AppRadius.smAll),
        ),
      ),
      AppSpacing.hXs,
      if (hits.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            '没有匹配的词条',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        )
      else ...<Widget>[
        if (people.isNotEmpty)
          _entryGroup(context, '人物', people, initiallyExpanded: true),
        if (nouns.isNotEmpty)
          _entryGroup(
            context,
            '名词 / 设定',
            nouns,
            initiallyExpanded: people.isEmpty,
          ),
      ],
      if (index.length < d.entryCount) ...<Widget>[
        AppSpacing.hXs,
        Text(
          '（只显示前 ${index.length} 条，完整内容请导入后查看）',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  Widget _entryGroup(
    BuildContext context,
    String label,
    List<WorldEntryPreview> items, {
    required bool initiallyExpanded,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Theme(
      // 去掉 ExpansionTile 默认的分隔线，列表里那两条横线很吵。
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: AppWeight.medium),
        ),
        subtitle: Text(
          '${items.length} 条',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: cs.onSurfaceVariant,
          ),
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final WorldEntryPreview e in items)
                  _entryChip(context, e.name, e.keys),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryChip(BuildContext context, String name, List<String> keys) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.xsAll,
      ),
      child: Text.rich(
        TextSpan(
          text: name,
          children: <InlineSpan>[
            if (keys.isNotEmpty)
              TextSpan(
                text: ' · ${keys.join('、')}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
          ],
        ),
        style: TextStyle(fontSize: AppFontSize.caption, color: cs.onSurface),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: AppWeight.medium),
    );
  }

  Widget _sampleCard(BuildContext context, Map<String, dynamic> entry) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String name = (entry['name'] ?? '').toString();
    final String description = (entry['description'] ?? '').toString();
    final String type = (entry['type'] ?? '').toString();
    final List<String> keys =
        (entry['keys'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: AppWeight.medium,
                  ),
                ),
              ),
              if (type.isNotEmpty)
                Text(
                  type == 'person' ? '人物' : '名词',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            AppSpacing.hXs,
            Text(description, style: theme.textTheme.bodySmall),
          ],
          if (keys.isNotEmpty) ...<Widget>[
            AppSpacing.hXs,
            Text(
              '触发词：${keys.join('、')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canImport = widget.importSink != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canImport && !_importing ? _import : null,
                icon: _importing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_importing ? '正在导入…' : '导入到我的世界'),
              ),
            ),
            if (!canImport) ...<Widget>[
              AppSpacing.hXs,
              Text(
                '当前环境没有可写入的本地世界（需要在主应用的社区里操作）',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
