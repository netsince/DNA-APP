import 'package:material_ui/material_ui.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/widgets/paged_list_body.dart';

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
      appBar: AppBar(title: const Text('消息通知')),
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
  int _unread = 0;
  bool _markingAll = false;

  /// 分页状态（加载中 / 加载更多 / 没有更多 / 页码 / 错误）统一由
  /// [PagedController] 管；未读数是列表附带的头部信息，不是分页状态。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final NotificationsData result = await _loader(page: page);
          // 每页都会带回最新未读数，只有成功时才覆盖。
          _unread = result.unreadCount;
          return PagedResult<Map<String, dynamic>>(
            items: result.items,
            hasMore: result.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '加载失败',
      );

  NotificationsLoader get _loader =>
      widget.loader ?? ApiClient.instance.getNotifications;

  ReadAllHandler get _readAll =>
      widget.readAll ?? ApiClient.instance.markAllNotificationsRead;

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

  Future<void> _markAllRead() async {
    if (_markingAll || _unread == 0) return;
    setState(() => _markingAll = true);
    try {
      await _readAll();
      if (!mounted) return;
      // 只把「已经加载到的行」就地标成已读：分页状态（页码 / 有没有更多）
      // 一点没变，重新拉一遍列表反而会丢滚动位置。
      final List<Map<String, dynamic>> marked = _paged.items
          .map(
            (Map<String, dynamic> n) => <String, dynamic>{
              ...n,
              'is_read': true,
            },
          )
          .toList();
      setState(() {
        _unread = 0;
        _paged.items
          ..clear()
          ..addAll(marked);
      });
      showSnack(context, '已全部标记为已读');
    } catch (e) {
      if (mounted) {
        showSnack(context, '操作失败：${describeError(e)}');
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  /// 按关联类型决定跳到哪：角色卡 → 卡片详情，世界卡 → 世界卡详情。
  void _openRelated(String type, String id) {
    if (type == 'world') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => WorldDetailPage(id: id)));
      return;
    }
    _openCard(id);
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
        Expanded(child: _buildList()),
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

  Widget _buildList() {
    // 五态 + 下拉刷新 + 触底加载由 [PagedListBody] 统一负责；宽窗口的版心
    // （审计 3.4「同一条内容，列表有版心、详情没有」）也交给它算，本页不再
    // 自己求 inset。
    return PagedListBody<Map<String, dynamic>>(
      controller: _paged,
      padding: const EdgeInsets.symmetric(vertical: 8),
      separator: (_, _) => const Divider(height: 1, indent: 16),
      empty: const EmptyState(icon: Icons.notifications_none, title: '暂时没有通知。'),
      itemBuilder: (BuildContext context, int index) {
        final n = _paged.items[index];
        final isRead = n['is_read'] == true;
        final message = (n['message'] ?? '').toString();
        final created = (n['created_at'] ?? '').toString();
        // 关联对象：优先用通用的 related_type / related_id；老服务端只给
        // related_card_id，回退成角色卡。
        final String relatedType =
            (n['related_type'] ?? (n['related_card_id'] != null ? 'card' : ''))
                .toString();
        final String relatedId = (n['related_id'] ?? n['related_card_id'] ?? '')
            .toString();
        final bool canOpen =
            relatedId.isNotEmpty &&
            (relatedType == 'card' || relatedType == 'world');
        final scheme = Theme.of(context).colorScheme;
        return ListTile(
          onTap: canOpen ? () => _openRelated(relatedType, relatedId) : null,
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
          trailing: !canOpen
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
