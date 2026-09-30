import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/utils/points_format.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 积分明细分页加载回调（默认走 [ApiClient.getPoints]）。
typedef PointsLoader = Future<PointsData> Function({int page});

/// 兑换回调（默认走 [ApiClient.redeemPoints]）。
typedef PointsRedeemer =
    Future<
      ({List<Map<String, dynamic>> results, int successCount, int failCount})
    >
    Function(List<String> codes);

/// 积分页：余额大卡 + 变化明细分页 + 兑换入口。
///
/// 对齐网页点数详情页（app/templates/points/detail.html）：
/// 顶部渐变余额卡，下方按时间倒序的明细分页（时间/变化/余额/来源/说明），
/// 提供「兑换」入口与站点配置的「获取积分」外链；滚动到底自动加载更多。
class PointsPage extends StatelessWidget {
  const PointsPage({super.key, this.loader, this.redeemer});

  /// 注入用：积分分页加载器（测试时替换为 stub）。
  final PointsLoader? loader;

  /// 注入用：兑换回调（测试时替换为 stub）。
  final PointsRedeemer? redeemer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的点数'),
        centerTitle: true,
        actions: <Widget>[
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PointsRedeemPage(loader: loader, redeemer: redeemer),
                ),
              );
            },
            icon: const Icon(Icons.redeem_outlined, size: 18),
            label: const Text('兑换'),
          ),
        ],
      ),
      body: PointsBody(loader: loader),
    );
  }
}

/// 积分明细主体（独立组件便于测试）。
class PointsBody extends StatefulWidget {
  const PointsBody({super.key, this.loader});

  final PointsLoader? loader;

  @override
  State<PointsBody> createState() => _PointsBodyState();
}

class _PointsBodyState extends State<PointsBody> {
  List<Map<String, dynamic>> _txs = const [];
  Decimal _balance = Decimal.zero;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  String? _error;

  PointsLoader get _loader => widget.loader ?? ApiClient.instance.getPoints;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = await _loader(page: page);
      if (!mounted) return;
      setState(() {
        if (reset) _txs = <Map<String, dynamic>>[];
        _txs = <Map<String, dynamic>>[..._txs, ...result.items];
        _page = page;
        _balance = result.balance;
        _noMore = !(result.page < result.pages);
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_txs.isEmpty) _error = '$e';
      });
    }
  }

  Future<void> _openGetPoints() async {
    final url = SiteConfig.instance.redeemCodeUrl;
    if (url.isEmpty) return;
    await confirmOpenBrowser(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildBalanceCard(context),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// 渐变余额大卡 + 「获取积分」外链（站点配置存在时显示）。
  Widget _buildBalanceCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[scheme.primaryContainer, scheme.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(kRadiusLg),
      ),
      child: Column(
        children: <Widget>[
          Text(
            '当前点数',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatPoints(_balance),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (SiteConfig.instance.redeemCodeUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _openGetPoints,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('获取积分'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading && _txs.isEmpty) {
      return const LoadingState();
    }
    if (_error != null && _txs.isEmpty) {
      return ErrorState(onRetry: () => _load(reset: true));
    }
    if (_txs.isEmpty) {
      return const EmptyState(icon: Icons.receipt_long_outlined, title: '暂无记录');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '变化明细',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: LoadMoreListView(
            itemCount: _txs.length,
            hasMore: !_noMore,
            onLoadMore: _load,
            onRefresh: () => _load(reset: true),
            padding: const EdgeInsets.symmetric(vertical: 4),
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final t = _txs[index];
              final delta = parsePoints(t['delta']);
              final balanceAfter = parsePoints(t['balance_after']);
              final reason = (t['reason'] ?? '').toString();
              final source = (t['source'] ?? '').toString();
              final created = (t['created_at'] ?? '').toString();
              final positive = delta >= Decimal.zero;
              return ListTile(
                title: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        reason.isEmpty ? source : reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      positive ? '+${formatPoints(delta)}' : formatPoints(delta),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: positive ? scheme.primary : scheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: <Widget>[
                      Text(
                        formatDateTime(created),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                      const SizedBox(width: 8),
                      if (source.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            source,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '余额 ${formatPoints(balanceAfter)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 兑换页：单码快捷 / 多行批量 + 兑换结果。
///
/// 对齐网页兑换页（app/templates/points/redeem.html）：
/// 一次最多 50 个、每分钟 2 次；失败提示保留在结果表；粘贴按钮读取剪贴板。
class PointsRedeemPage extends StatefulWidget {
  const PointsRedeemPage({super.key, this.loader, this.redeemer});

  final PointsLoader? loader;
  final PointsRedeemer? redeemer;

  @override
  State<PointsRedeemPage> createState() => _PointsRedeemPageState();
}

class _PointsRedeemPageState extends State<PointsRedeemPage> {
  final _singleController = TextEditingController();
  final _multiController = TextEditingController();
  bool _isMulti = false;
  bool _redeeming = false;
  String? _error;
  List<Map<String, dynamic>> _results = const [];

  PointsRedeemer get _redeemer =>
      widget.redeemer ?? ApiClient.instance.redeemPoints;

  @override
  void dispose() {
    _singleController.dispose();
    _multiController.dispose();
    super.dispose();
  }

  void _toggleMode() => setState(() => _isMulti = !_isMulti);

  Future<void> _paste() async {
    try {
      final text = await Clipboard.getData(Clipboard.kTextPlain);
      final value = text?.text?.trim() ?? '';
      if (value.isEmpty) return;
      _singleController.text = value;
    } catch (_) {
      // 剪贴板不可用时静默。
    }
  }

  Future<void> _redeem() async {
    if (_redeeming) return;
    // 单码模式取单码输入；多行模式按行拆分去重。
    final raw = _isMulti ? _multiController.text : _singleController.text;
    final codes = {
      ...raw
          .split(RegExp(r'[\r\n,，\s]+'))
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty),
    }.toList();
    if (codes.isEmpty) {
      setState(() => _error = '请输入至少一个兑换码');
      return;
    }
    if (codes.length > 50) {
      setState(() => _error = '一次最多兑换 50 个兑换码');
      return;
    }
    setState(() {
      _redeeming = true;
      _error = null;
      _results = const [];
    });
    try {
      final result = await _redeemer(codes);
      if (!mounted) return;
      setState(() => _results = result.results);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.successCount > 0
                ? '兑换完成：成功 ${result.successCount} 个，失败 ${result.failCount} 个'
                : '全部兑换失败，请检查兑换码',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('兑换点数'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: const Text(
              '一次最多兑换 50 个兑换码；每分钟最多兑换 2 次；连续多次兑换失败将临时禁用兑换 1 小时。',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          if (_isMulti) ...<Widget>[
            TextField(
              controller: _multiController,
              enabled: !_redeeming,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: '批量兑换码（一行一个）',
                hintText: '每行输入一个兑换码',
                border: OutlineInputBorder(),
              ),
            ),
          ] else ...<Widget>[
            TextField(
              controller: _singleController,
              enabled: !_redeeming,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: '输入兑换码',
                hintText: '例如：DNA-XXXX-XXXX',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_outlined),
                  tooltip: '粘贴',
                  onPressed: _redeeming ? null : _paste,
                ),
              ),
              onSubmitted: (_) => _redeem(),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _redeeming ? null : _toggleMode,
              child: Text(_isMulti ? '单码快捷兑换' : '多行批量兑换（批量粘贴）'),
            ),
          ),
          if (_error != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          ],
          const SizedBox(height: 12),
          AsyncActionButton(
            variant: AsyncButtonVariant.filled,
            enabled: !_redeeming,
            onPressed: _redeem,
            loadingSize: 20,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('兑换'),
          ),
          if (_results.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              '兑换结果',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            for (final r in _results)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    r['ok'] == true
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: r['ok'] == true ? scheme.primary : scheme.error,
                  ),
                  title: Text(
                    (r['code'] ?? '').toString(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: Text(
                    (r['message'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: r['ok'] == true
                          ? scheme.onSurfaceVariant
                          : scheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
