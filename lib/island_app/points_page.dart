import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/utils/points_format.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/widgets/load_more_list.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import '../widgets/form_draft.dart';
import '../widgets/submit_form.dart';
import '../theme/tokens.dart';

/// 积分明细分页加载回调（默认走 [ApiClient.getPoints]）。
typedef PointsLoader = Future<PointsData> Function({int page});

/// 兑换回调（默认走 [ApiClient.redeemPoints]）。
typedef PointsRedeemer =
    Future<
      ({List<Map<String, dynamic>> results, int successCount, int failCount})
    >
    Function(List<String> codes);

/// 数字列用等宽数字（tabular figures）。
///
/// 明细是"时间 / 变化 / 余额 / 来源"四列数据：默认字体的 `1` 比 `8` 窄，
/// 上下串起来时小数点与个位对不齐，扫一列金额很费劲。
/// 全项目此前 0 处等宽数字（审计 3.3）。
const List<FontFeature> _tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// 金额 / 余额列的**最小宽**（不再是定死宽）。
///
/// 回滚 R7：定死 92dp 时位数一多就顶出去。改成「最小宽 + 自适应」——
/// 短金额靠右对齐、上下仍然成列；长金额向左撑开，不溢出也不裁切。
const double _amountColumnMinWidth = 72;

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
  /// 余额不是分页状态（每页都会带回最新值），留在页面里。
  Decimal _balance = Decimal.zero;

  /// 分页状态（加载中 / 加载更多 / 没有更多 / 页码 / 错误）统一由
  /// [PagedController] 管，页面只提供「怎么取一页」。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final PointsData result = await _loader(page: page);
          // 每页都会带回最新余额，只有成功时才覆盖。
          _balance = result.balance;
          return PagedResult<Map<String, dynamic>>(
            items: result.items,
            hasMore: result.page < result.pages,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '加载失败',
      );

  PointsLoader get _loader => widget.loader ?? ApiClient.instance.getPoints;

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
      margin: AppInsets.card,
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
              color: scheme.onPrimaryContainer.withValues(alpha: AppAlpha.mutedStrong),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatPoints(_balance),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: AppWeight.medium,
              fontFeatures: _tabularFigures,
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
    if (_paged.isLoading && _paged.items.isEmpty) {
      return const LoadingState();
    }
    if (_paged.error != null && _paged.items.isEmpty) {
      return ErrorState(message: _paged.error!, onRetry: _paged.refresh);
    }
    if (_paged.items.isEmpty) {
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
            loading: _paged.isLoading,
            itemCount: _paged.items.length,
            hasMore: _paged.hasMore && _paged.items.isNotEmpty,
            onLoadMore: _paged.loadMore,
            onRefresh: _paged.refresh,
            padding: const EdgeInsets.symmetric(vertical: 4),
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              final t = _paged.items[index];
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
                    // 金额列：**最小宽 + 自适应**右对齐（回滚 R7）。
                    // 等宽数字保留，短金额仍能上下成列；长金额向左撑开，
                    // 不溢出、不裁切。
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: _amountColumnMinWidth,
                      ),
                      child: Text(
                        positive
                            ? '+${formatPoints(delta)}'
                            : formatPoints(delta),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: positive ? scheme.primary : scheme.error,
                          fontWeight: FontWeight.w500,
                          fontFeatures: _tabularFigures,
                        ),
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
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            source,
                            style: TextStyle(
                              fontSize: AppFontSize.tiny,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Spacer(),
                      // 余额列同样「最小宽 + 自适应」，与金额列同一套规则。
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: _amountColumnMinWidth,
                        ),
                        child: Text(
                          '余额 ${formatPoints(balanceAfter)}',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                            fontFeatures: _tabularFigures,
                          ),
                        ),
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
  // 两个输入框的控制器统一由草稿持有。
  final FormDraft _draft = FormDraft(
    textFields: const <String>['single', 'multi'],
  );

  // 兑换中的忙态 + 失败原因（失败原因就地显示，前缀沿用原文案）。
  final SubmitFormState _submit = SubmitFormState();

  bool _isMulti = false;

  /// 本地校验提示（空码 / 超过 50 个），与提交失败分开显示。
  String? _error;
  List<Map<String, dynamic>> _results = const [];

  PointsRedeemer get _redeemer =>
      widget.redeemer ?? ApiClient.instance.redeemPoints;

  @override
  void initState() {
    super.initState();
    // 提交态变了就重建：输入框 / 切换按钮 / 兑换按钮一起跟着禁用。
    _submit.addListener(_onSubmitChanged);
  }

  /// 提交态（忙 / 失败原因）变了就重建。
  void _onSubmitChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 只摘监听、不 dispose _submit：兑换请求可能在页面 pop 之后才回来，
    // 那时 run() 还会 notifyListeners()。
    _submit.removeListener(_onSubmitChanged);
    _draft.dispose();
    super.dispose();
  }

  void _toggleMode() => setState(() => _isMulti = !_isMulti);

  Future<void> _paste() async {
    try {
      final text = await Clipboard.getData(Clipboard.kTextPlain);
      final value = text?.text?.trim() ?? '';
      if (value.isEmpty) return;
      _draft.controller('single').text = value;
    } catch (_) {
      // 剪贴板不可用时静默。
    }
  }

  Future<void> _redeem() async {
    if (_submit.busy) return;
    // 每次尝试先清掉上一次的提交失败横幅（对应原来「开始请求即清空 _error」）。
    _submit.clearError();
    // 单码模式取单码输入；多行模式按行拆分去重。
    final raw = _isMulti ? _draft.rawText('multi') : _draft.rawText('single');
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
      _error = null;
      _results = const [];
    });
    await _submit.run(
      errorPrefix: '兑换失败',
      action: () async {
        final result = await _redeemer(codes);
        if (!mounted) return;
        setState(() => _results = result.results);
        showSnack(context, result.successCount > 0
                  ? '兑换完成：成功 ${result.successCount} 个，失败 ${result.failCount} 个'
                  : '全部兑换失败，请检查兑换码',);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('兑换点数')),
      body: ListView(
        padding: AppInsets.card,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: AppAlpha.a40),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: const Text(
              '一次最多兑换 50 个兑换码；每分钟最多兑换 2 次；连续多次兑换失败将临时禁用兑换 1 小时。',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                height: AppLineHeight.body,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isMulti) ...<Widget>[
            TextField(
              controller: _draft.controller('multi'),
              enabled: !_submit.busy,
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
              controller: _draft.controller('single'),
              enabled: !_submit.busy,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: '输入兑换码',
                hintText: '例如：DNA-XXXX-XXXX',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_outlined),
                  tooltip: '粘贴',
                  onPressed: _submit.busy ? null : _paste,
                ),
              ),
              onSubmitted: (_) => _redeem(),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submit.busy ? null : _toggleMode,
              child: Text(_isMulti ? '单码快捷兑换' : '多行批量兑换（批量粘贴）'),
            ),
          ),
          if (_error != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          ],
          // 兑换失败的真实原因就地显示（前缀沿用原文案「兑换失败」）。
          FormErrorBanner(message: _submit.errorText),
          const SizedBox(height: 12),
          AsyncActionButton(
            variant: AsyncButtonVariant.filled,
            enabled: !_submit.busy,
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
            // 兑换结果是同构的行：排成 list + Divider，而不是一行一张卡
            // （审计 3.3）。行内边距交给 ListTile，横向对齐交给页面 padding。
            for (int i = 0; i < _results.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  _results[i]['ok'] == true
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: _results[i]['ok'] == true
                      ? scheme.primary
                      : scheme.error,
                ),
                title: Text(
                  (_results[i]['code'] ?? '').toString(),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                trailing: Text(
                  (_results[i]['message'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: _results[i]['ok'] == true
                        ? scheme.onSurfaceVariant
                        : scheme.error,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
