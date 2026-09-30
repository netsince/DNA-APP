import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 我的处罚加载回调（默认走 [ApiClient.getPunishments]）。
typedef PunishmentsLoader = Future<PunishmentsData> Function();

/// 处罚申诉回调（默认走 [ApiClient.submitPunishmentAppeal]）。
typedef PunishmentAppealHandler = Future<Map<String, dynamic>> Function(
  int punishmentId,
  String appealReason,
);

/// 我的处罚页：处罚明细列表（对齐网页 /my/punishments）。
class PunishmentsPage extends StatelessWidget {
  const PunishmentsPage({super.key, this.loader, this.appealHandler, this.isLoggedIn});

  final PunishmentsLoader? loader;
  final PunishmentAppealHandler? appealHandler;

  /// 注入用：登录态覆盖（测试时可传 true）。
  final bool? isLoggedIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的处罚'), centerTitle: true),
      body: PunishmentsBody(
        loader: loader,
        appealHandler: appealHandler,
        isLoggedIn: isLoggedIn,
      ),
    );
  }
}

/// 我的处罚主体（独立组件便于测试）。
class PunishmentsBody extends StatefulWidget {
  const PunishmentsBody({
    super.key,
    this.loader,
    this.appealHandler,
    this.isLoggedIn,
  });

  final PunishmentsLoader? loader;
  final PunishmentAppealHandler? appealHandler;

  /// 注入用：登录态覆盖（默认读 [AuthSession]；测试时可传 true 跳过登录检查）。
  final bool? isLoggedIn;

  @override
  State<PunishmentsBody> createState() => _PunishmentsBodyState();
}

class _PunishmentsBodyState extends State<PunishmentsBody> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  PunishmentsLoader get _loader =>
      widget.loader ?? ApiClient.instance.getPunishments;

  PunishmentAppealHandler get _appealHandler =>
      widget.appealHandler ?? ApiClient.instance.submitPunishmentAppeal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!(widget.isLoggedIn ?? AuthSession.instance.isLoggedIn)) {
      setState(() {
        _loading = false;
        _error = '请先登录后再查看';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _loader();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 提交申诉：底部输入框 + 提交按钮。
  ///
  /// 提交请求在弹层内完成：点击「提交申诉」后按钮立即禁用并显示加载圆圈，
  /// 等待服务器返回（成功/失败）后再关闭弹层并刷新列表，避免重复提交。
  Future<void> _appeal(Map<String, dynamic> p) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _AppealSheet(
        punishment: p,
        handler: _appealHandler,
      ),
    );
    if (updated == null) return;
    if (!mounted) return;
    setState(() {
      _items = <Map<String, dynamic>>[
        for (final it in _items)
          if ((it['id'] as num?)?.toInt() == updated['id']) updated else it,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _error == '请先登录后再查看' ? null : _load,
      );
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.gavel_outlined,
        title: '暂无处罚记录',
      );
    }
    return AppRefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _PunishmentCard(
          p: _items[index],
          onAppeal: () => _appeal(_items[index]),
        ),
      ),
    );
  }
}

/// 单条处罚卡：类型/原因/时间/状态 + 申诉按钮。
class _PunishmentCard extends StatelessWidget {
  const _PunishmentCard({required this.p, required this.onAppeal});

  final Map<String, dynamic> p;
  final VoidCallback onAppeal;

  String _statusLabel() {
    final status = (p['status'] ?? '').toString();
    switch (status) {
      case 'active':
        return '生效中';
      case 'expired':
        return '已到期';
      case 'revoked':
        return '已撤销';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch ((p['status'] ?? '').toString()) {
      case 'active':
        return scheme.error;
      case 'revoked':
        return scheme.primary;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reason = (p['reason'] ?? '').toString();
    final created = (p['created_at'] ?? '').toString();
    final expires = (p['expires_at'] ?? '').toString();
    final canAppeal = p['can_appeal'] == true;
    final appealed = p['appealed'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    (p['type_label'] ?? '处罚').toString(),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(context),
                    ),
                  ),
                ),
              ],
            ),
            if (reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(reason, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Text(
              '处罚时间 ${formatDateTime(created)}'
              '${expires.isNotEmpty ? '\n到期时间 ${formatDateTime(expires)}' : ''}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            if (appealed) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '已提交申诉，等待处理',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ] else if (canAppeal) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onAppeal,
                  child: const Text('申诉'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 申诉输入弹层：在弹层内完成提交请求。
///
/// 点击「提交申诉」后按钮立即禁用并显示加载圆圈，等待服务器返回；成功才
/// 关闭弹层并返回申诉理由，失败留在弹层提示（不丢失已输入内容）。
class _AppealSheet extends StatefulWidget {
  const _AppealSheet({required this.punishment, required this.handler});

  final Map<String, dynamic> punishment;
  final PunishmentAppealHandler handler;

  @override
  State<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<_AppealSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = '请输入申诉理由');
      return;
    }
    setState(() => _error = null);
    try {
      final updated = await widget.handler(
        (widget.punishment['id'] as num).toInt(),
        reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '提交失败：$e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '申诉「${widget.punishment['type_label'] ?? ''}」',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '请说明申诉理由…',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          AsyncActionButton(
            variant: AsyncButtonVariant.filled,
            onPressed: _submit,
            child: const Text('提交申诉'),
          ),
        ],
      ),
    );
  }
}