import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 通知分页加载回调（默认走 [ApiClient.getNotifications]）。
typedef NotificationsLoader = Future<NotificationsData> Function({int page});

/// 全部标记已读回调（默认走 [ApiClient.markAllNotificationsRead]）。
typedef ReadAllHandler = Future<void> Function();

/// 通知页：未读徽标 + 消息列表（分页）+ 全部已读。
///
/// 对齐网页通知页（app/templates/user/notifications.html）：
/// 顶部显示未读数徽标，有未读时提供「全部已读」；每条通知展示未读圆点、
/// 消息内容与时间；点击带相关卡片的通知可打开角色卡详情；滚动到底自动加载更多。
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, this.loader, this.readAll});

  /// 注入用：通知分页加载器（测试时替换为 stub）。
  final NotificationsLoader? loader;

  /// 注入用：全部标记已读（测试时替换为 stub）。
  final ReadAllHandler? readAll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('消息通知'), centerTitle: true),
      body: NotificationsBody(loader: loader, readAll: readAll),
    );
  }
}

/// 通知列表主体（独立组件便于测试）。
class NotificationsBody extends StatefulWidget {
  const NotificationsBody({super.key, this.loader, this.readAll});

  final NotificationsLoader? loader;
  final ReadAllHandler? readAll;

  @override
  State<NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends State<NotificationsBody> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  int _unread = 0;
  bool _markingAll = false;
  String? _error;

  NotificationsLoader get _loader =>
      widget.loader ?? ApiClient.instance.getNotifications;

  ReadAllHandler get _readAll =>
      widget.readAll ?? ApiClient.instance.markAllNotificationsRead;

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
        if (reset) _items = <Map<String, dynamic>>[];
        _items = <Map<String, dynamic>>[..._items, ...result.items];
        _page = page;
        _unread = result.unreadCount;
        _noMore = !result.hasNext;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_items.isEmpty) _error = '$e';
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unread == 0) return;
    setState(() => _markingAll = true);
    try {
      await _readAll();
      if (!mounted) return;
      setState(() {
        _unread = 0;
        _items = _items.map((n) {
          return <String, dynamic>{...n, 'is_read': true};
        }).toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已全部标记为已读')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _openCard(String cardId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: cardId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// 头部：未读徽标 + 全部已读（有未读时显示）。
  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          if (_unread > 0)
            Text(
              '$_unread 未读',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Text(
              '全部已读',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const Spacer(),
          if (_unread > 0)
            AsyncActionButton(
              variant: AsyncButtonVariant.text,
              enabled: !_markingAll,
              loadingSize: 16,
              onPressed: _markAllRead,
              child: const Text('全部已读'),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const LoadingState();
    }
    if (_error != null && _items.isEmpty) {
      return ErrorState(onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none, title: '暂时没有通知。');
    }
    return LoadMoreListView(
      itemCount: _items.length,
      hasMore: !_noMore,
      onLoadMore: _load,
      onRefresh: () => _load(reset: true),
      padding: const EdgeInsets.symmetric(vertical: 8),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final n = _items[index];
        final isRead = n['is_read'] == true;
        final message = (n['message'] ?? '').toString();
        final created = (n['created_at'] ?? '').toString();
        final cardId = (n['related_card_id'] ?? '').toString();
        final scheme = Theme.of(context).colorScheme;
        return ListTile(
          onTap: cardId.isEmpty ? null : () => _openCard(cardId),
          leading: SizedBox(
            width: 10,
            child: isRead
                ? null
                : Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          title: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isRead ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              formatRelativeTime(created),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
          trailing: cardId.isEmpty
              ? null
              : Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.outlineVariant,
                ),
        );
      },
    );
  }
}
