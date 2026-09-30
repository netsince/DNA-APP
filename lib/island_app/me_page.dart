import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/my_cards_page.dart';
import 'package:dna/island_app/my_collections_page.dart';
import 'package:dna/island_app/notifications_page.dart';
import 'package:dna/island_app/points_page.dart';
import 'package:dna/island_app/profile_edit_page.dart';
import 'package:dna/island_app/punishments_page.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/tickets_page.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 「我」页面：未登录时显示登录表单；已登录时显示个人主页。
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthSession.instance,
      builder: (context, _) {
        final auth = AuthSession.instance;
        final user = auth.user;
        if (auth.isLoggedIn && user != null) {
          return ProfileView(
            username: (user['username'] ?? '').toString(),
            isSelf: true,
          );
        }
        return const _LoginView();
      },
    );
  }
}

/// 头像渲染：base64 data URL -> Image.memory；否则按网络图/占位处理。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatar, this.radius = 40});

  final String avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    final a = avatar;
    if (a.isEmpty) {
      child = Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant);
    } else if (a.startsWith('data:')) {
      final comma = a.indexOf(',');
      final b64 = comma >= 0 ? a.substring(comma + 1) : a;
      try {
        final bytes = base64Decode(b64);
        child = Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {
        child = Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant);
      }
    } else {
      child = Image.network(
        ServerConfig.resolveUrl(a),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      child: ClipOval(child: child),
    );
  }
}

/// 未登录：登录表单 + 跳转注册。
class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final id = _identifier.text.trim();
    final pw = _password.text;
    if (id.isEmpty || pw.isEmpty) {
      setState(() => _error = '请输入用户名/邮箱和密码');
      return;
    }
    final err = await AuthSession.instance.login(id, pw);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
    }
  }

  Future<void> _openRegister() async {
    await confirmOpenBrowser(context, ServerConfig.resolveUrl('/auth/register'));
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthSession.instance;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.account_circle, size: 64, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                '登录 ${SiteConfig.instance.siteName}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Text(
                '登录后可查看个人主页',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _identifier,
                enabled: !auth.busy,
                decoration: const InputDecoration(
                  labelText: '用户名 / 邮箱',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !auth.busy,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 20),
              AsyncActionButton(
                variant: AsyncButtonVariant.filled,
                enabled: !auth.busy,
                onPressed: _login,
                loadingSize: 20,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('登录'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: auth.busy ? null : _openRegister,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('注册（在浏览器中打开）'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 个人主页加载回调（默认走 [ApiClient.getUserProfile]）。
typedef ProfileLoader = Future<Map<String, dynamic>> Function(
  String username, {
  int page,
});

/// 关注/取关回调（返回是否「已关注」；默认走 [ApiClient.toggleFollow]）。
typedef ProfileFollowToggler = Future<bool> Function(String username);

/// 用户角色卡评论加载回调（默认走 [ApiClient.getUserComments]）。
typedef ProfileCommentsLoader =
    Future<Map<String, dynamic>> Function(String username, {int page});

/// 用户茶馆帖子加载回调（默认走 [ApiClient.getUserTeahousePosts]）。
typedef ProfileTeahouseLoader =
    Future<Map<String, dynamic>> Function(String username, {int page});

/// 个人主页（自己或他人共用）：身份头卡 + 可点击统计 + 内容标签。
///
/// [isSelf] 为 true 时额外显示「这是你」与退出按钮。
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.username,
    this.isSelf = false,
    this.profileLoader,
    this.commentsLoader,
    this.teahouseLoader,
    this.followToggler,
    this.clipboardWriter,
    this.isLoggedIn,
  });

  final String username;
  final bool isSelf;

  /// 注入用：主页数据加载器（测试时替换为 stub）。
  final ProfileLoader? profileLoader;

  /// 注入用：用户评论加载器（测试时替换为 stub）。
  final ProfileCommentsLoader? commentsLoader;

  /// 注入用：用户茶馆帖子加载器（测试时替换为 stub）。
  final ProfileTeahouseLoader? teahouseLoader;

  /// 注入用：关注切换回调（测试时替换为 stub）。
  final ProfileFollowToggler? followToggler;

  /// 注入用：剪贴板写入（测试时替换为 stub）。
  final Future<void> Function(String text)? clipboardWriter;

  /// 注入用：登录态覆盖（默认读 [AuthSession]）。
  final bool? isLoggedIn;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final List<Map<String, dynamic>> _cards = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  int _cardTotal = 0;
  int _followerCount = 0;
  int _followingCount = 0;

  // 评论 tab 分页状态
  bool _commentsLoading = false;
  bool _commentsLoadingMore = false;
  bool _commentsNoMore = false;
  int _commentsPage = 0;

  // 茶馆 tab 分页状态
  final List<Map<String, dynamic>> _teahouse = <Map<String, dynamic>>[];
  bool _teahouseLoading = false;
  bool _teahouseLoadingMore = false;
  bool _teahouseNoMore = false;
  int _teahousePage = 0;

  /// 当前登录用户是否已关注该主页用户（他人主页关注按钮的初始状态）。
  bool _isFollowing = false;

  /// 关注切换请求进行中（按钮禁用态）。
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile(reset: true);
    _loadComments(reset: true);
    _loadTeahouse(reset: true);
  }

  /// 用户评论分页加载（[reset] 为 true 时重拉第一页）。
  Future<void> _loadComments({bool reset = false}) async {
    if (_commentsLoadingMore || (!reset && _commentsNoMore)) return;
    setState(() {
      if (reset) _commentsLoading = true;
      _commentsLoadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _commentsPage + 1;
      final data = await (widget.commentsLoader ??
          ApiClient.instance.getUserComments)(widget.username, page: page);
      if (!mounted) return;
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (reset) _comments.clear();
        _comments.addAll(items);
        _commentsPage = page;
        _commentsNoMore = items.isEmpty || data['has_next'] != true;
        _commentsLoading = false;
        _commentsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _commentsLoading = false;
          _commentsLoadingMore = false;
        });
      }
    }
  }

  /// 用户茶馆帖子分页加载（[reset] 为 true 时重拉第一页）。
  Future<void> _loadTeahouse({bool reset = false}) async {
    if (_teahouseLoadingMore || (!reset && _teahouseNoMore)) return;
    setState(() {
      if (reset) _teahouseLoading = true;
      _teahouseLoadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _teahousePage + 1;
      final data = await (widget.teahouseLoader ??
          ApiClient.instance.getUserTeahousePosts)(widget.username, page: page);
      if (!mounted) return;
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (reset) _teahouse.clear();
        _teahouse.addAll(items);
        _teahousePage = page;
        _teahouseNoMore = items.isEmpty || data['has_next'] != true;
        _teahouseLoading = false;
        _teahouseLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _teahouseLoading = false;
          _teahouseLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadProfile({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final data = await (widget.profileLoader ??
          ApiClient.instance.getUserProfile)(widget.username, page: page);
      if (!mounted) return;
      final u = data['user'];
      final cards = data['cards'];
      final items = (cards is Map && cards['items'] is List)
          ? (cards['items'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (u is Map) _user = u.map((k, v) => MapEntry(k.toString(), v));
        if (reset) _cards.clear();
        _cards.addAll(items);
        _page = page;
        _followerCount = (data['follower_count'] as num?)?.toInt() ?? 0;
        _followingCount = (data['following_count'] as num?)?.toInt() ?? 0;
        _isFollowing = data['is_following'] == true;
        if (cards is Map) {
          _cardTotal = ((cards['total'] as num?) ?? 0).toInt();
        }
        if (items.isEmpty) _noMore = true;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _openFollowList(bool followers) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowListPage(
          username: widget.username,
          followers: followers,
        ),
      ),
    );
  }

  /// 非自己且非当前登录用户本人时才显示关注按钮。
  bool get _canFollow {
    if (widget.isSelf) return false;
    if (!_loggedIn) return false;
    final me = AuthSession.instance.user;
    final meName = me != null ? (me['username'] ?? '').toString() : '';
    return meName != widget.username;
  }

  /// 登录态：优先取注入值（测试可控），否则读 [AuthSession]。
  bool get _loggedIn => widget.isLoggedIn ?? AuthSession.instance.isLoggedIn;

  /// 关注 / 取消关注该主页用户（他人主页；未登录或关注自己时提示）。
  Future<void> _toggleFollow() async {
    if (!_loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再关注')),
      );
      return;
    }
    setState(() => _followBusy = true);
    try {
      final following =
          await (widget.followToggler ?? ApiClient.instance.toggleFollow)(
        widget.username,
      );
      if (!mounted) return;
      setState(() {
        _isFollowing = following;
        final next = _followerCount + (following ? 1 : -1);
        _followerCount = next < 0 ? 0 : next;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// 复制该主页的网页版链接（`<服务器>/user/<username>`）。
  Future<void> _copyProfileLink() async {
    final url = ServerConfig.resolveUrl('/user/${widget.username}');
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未配置服务器地址')),
      );
      return;
    }
    final writer = widget.clipboardWriter ??
        (text) => Clipboard.setData(ClipboardData(text: text));
    await writer(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制主页链接')),
      );
    }
  }

  /// 下拉刷新：重新拉取个人资料与评论第一页。
  Future<void> _refresh() async {
    if (_loading) return;
    await Future.wait([
      _loadProfile(reset: true),
      _loadComments(reset: true),
      _loadTeahouse(reset: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    if (_loading && u == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // 主页式布局：身份头卡随内容上滚消失，TabBar 吸顶，内容占满剩余空间。
    return DefaultTabController(
      length: 3,
      child: AppRefreshIndicator(
        onRefresh: _refresh,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => <Widget>[
            SliverToBoxAdapter(child: _buildHeader(context, u)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarHeader(
                child: const TabBar(
                  tabs: <Widget>[
                    Tab(text: '角色卡'),
                    Tab(text: '茶馆'),
                    Tab(text: '评论'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: <Widget>[
              _buildCardsTab(context),
              _buildTeahouseTab(context),
              _buildCommentsTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, dynamic>? u) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = u != null ? (u['nickname'] ?? '').toString() : '';
    final username = u != null ? (u['username'] ?? '').toString() : widget.username;
    final uid = u != null ? (u['id'] ?? '').toString() : '';
    final verified = u != null && u['verified'] == true;
    final bio = u != null ? (u['bio'] ?? '').toString() : '';
    final location = u != null ? (u['location'] ?? '').toString() : '';
    final join = u != null ? _joinDate((u['created_at'] ?? '').toString()) : '';

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Avatar(
                avatar: u != null ? (u['avatar'] ?? '').toString() : '',
                radius: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            nickname.isEmpty ? username : nickname,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (verified) ...<Widget>[
                          const SizedBox(width: 6),
                          Icon(Icons.verified, size: 18, color: scheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isSelf
                          ? '@$username · UID $uid · 这是你'
                          : '@$username · UID $uid',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (verified) ...<Widget>[
                      const SizedBox(height: 6),
                      _verifiedBadge(context, u),
                    ],
                  ],
                ),
              ),
              if (!widget.isSelf) ...<Widget>[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _copyProfileLink,
                  tooltip: '复制主页链接',
                  icon: const Icon(Icons.link, size: 20),
                ),
                if (_canFollow)
                  AsyncActionButton(
                    variant: AsyncButtonVariant.tonal,
                    enabled: !_followBusy,
                    onPressed: _toggleFollow,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _isFollowing
                          ? scheme.surfaceContainerHigh
                          : null,
                      foregroundColor: _isFollowing
                          ? scheme.onSurfaceVariant
                          : null,
                    ),
                    child: Text(_isFollowing ? '已关注' : '关注'),
                  ),
              ] else ...<Widget>[
                const SizedBox(width: 8),
                // 自我管理入口收敛到 ⋮ 菜单，避免与昵称/认证挤在一起。
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'edit') _openEditProfile(context);
                    if (v == 'logout') _confirmLogout(context);
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('编辑资料'),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout),
                        title: Text('退出登录'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _buildStats(context),
          if (widget.isSelf) ...<Widget>[
            const SizedBox(height: 16),
            _buildSelfEntries(context),
          ],
          if (bio.isNotEmpty || location.isNotEmpty || join.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            if (bio.isNotEmpty)
              Text(
                bio,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.5,
                    ),
              ),
            if (location.isNotEmpty || join.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: <Widget>[
                    if (location.isNotEmpty)
                      _meta(context, Icons.place_outlined, location),
                    if (join.isNotEmpty)
                      _meta(context, Icons.calendar_today_outlined, '$join 加入'),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 认证徽章：展示管理员授予的认证说明（如「官方」「知名创作者」），缺省「认证」。
  Widget _verifiedBadge(BuildContext context, Map<String, dynamic>? u) {
    final scheme = Theme.of(context).colorScheme;
    final label =
        u != null ? (u['verified_label'] ?? '').toString().trim() : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.verified, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label.isEmpty ? '认证' : label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  /// 统计行：关注 / 粉丝 / 角色卡，点击可打开对应列表。
  Widget _buildStats(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List<Widget>.generate(3, (_) {
          return Container(
            width: 56,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        _stat(context, '关注', _followingCount, () => _openFollowList(false)),
        _stat(context, '粉丝', _followerCount, () => _openFollowList(true)),
        _stat(context, '角色卡', _cardTotal, null),
      ],
    );
  }

  /// 自己可见的快捷入口：消息通知 / 我的点数 / 我的处罚 / 我的收藏 / 我的点赞。
  /// 用 [Wrap] 排列，窄屏自动换行、宽屏一行展示。
  Widget _buildSelfEntries(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.notifications_outlined,
            '消息通知',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationsPage(),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.redeem_outlined,
            '我的点数',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PointsPage(),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.support_agent,
            '我的工单',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TicketsPage()),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.gavel_outlined,
            '我的处罚',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PunishmentsPage(),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.badge_outlined,
            '我的角色卡',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MyCardsPage()),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.bookmark_outline,
            '我的收藏',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MyCollectionsPage(
                    title: '我的收藏',
                    loader: ApiClient.instance.getMyFavorites,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 76,
          child: _entry(
            context,
            Icons.favorite_outline,
            '我的点赞',
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MyCollectionsPage(
                    title: '我的点赞',
                    loader: ApiClient.instance.getMyLikes,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int value, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    final column = Column(
      children: <Widget>[
        Text(
          '$value',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    if (onTap == null) return column;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: column,
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildCardsTab(BuildContext context) {
    if (_loading && _cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cards.isEmpty) {
      return _emptyTab('角色卡', '还没有发布任何角色卡');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadProfile();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: ResponsiveCardGrid(
              cards: _cards,
              minColumnWidth: 180,
              maxColumns: 5,
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _emptyTab(String title, String message) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(icon: Icons.inbox_outlined, title: title, message: message),
        ),
      ],
    );
  }

  /// 切到茶馆 tab 且当前是空态（含曾加载失败、登录后未重拉等）时自动重拉首页，
  /// 避免启动阶段登录态未就绪导致 401 后一直停留在「还没有发布茶馆帖子」。
  void _onTeahouseTabActive() {
    if (!mounted) return;
    if (_teahouse.isEmpty && !_teahouseLoading) {
      _loadTeahouse(reset: true);
    }
  }

  /// 切到评论 tab 且当前是空态时自动重拉，同上避免启动 401 后残留空态。
  void _onCommentsTabActive() {
    if (!mounted) return;
    if (_comments.isEmpty && !_commentsLoading) {
      _loadComments(reset: true);
    }
  }

  /// 茶馆 tab：用户发布的茶馆帖子（分页加载，点击进入帖子详情）。
  Widget _buildTeahouseTab(BuildContext context) {
    return _ReloadOnActive(
      onActive: _onTeahouseTabActive,
      child: _buildTeahouseContent(context),
    );
  }

  Widget _buildTeahouseContent(BuildContext context) {
    if (_teahouseLoading && _teahouse.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_teahouse.isEmpty && !_teahouseLoading) {
      return _emptyTab('茶馆', '还没有发布茶馆帖子');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadTeahouse();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _teahouse.length + (_teahouseLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
        itemBuilder: (context, index) {
          if (index >= _teahouse.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final raw = _teahouse[index];
          final post = TeaPost.fromJson(raw);
          if (post.isDeleted) return const SizedBox.shrink();
          return TeahousePostTile(
            post: post,
            onTap: () => _openTeahousePost(post.idInt),
          );
        },
      ),
    );
  }

  /// 点击茶馆帖子：进入茶馆帖子详情页。
  void _openTeahousePost(int postId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahousePostPage(postId: postId),
      ),
    );
  }

  /// 评论 tab：用户发表的角色卡评论（分页加载，点击进入对应卡片）。
  Widget _buildCommentsTab(BuildContext context) {
    return _ReloadOnActive(
      onActive: _onCommentsTabActive,
      child: _buildCommentsContent(context),
    );
  }

  Widget _buildCommentsContent(BuildContext context) {
    if (_commentsLoading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_comments.isEmpty && !_commentsLoading) {
      return _emptyTab('评论', '还没有发表评论');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadComments();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _comments.length + (_commentsLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
        itemBuilder: (context, index) {
          if (index >= _comments.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final c = _comments[index];
          return _CommentTile(
            comment: c,
            onTap: () => _openCommentCard(c),
          );
        },
      ),
    );
  }

  /// 退出登录：先弹确认框，确认后才真正登出。
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthSession.instance.logout();
  }

  /// 打开个人资料编辑页；保存成功后刷新当前资料。
  Future<void> _openEditProfile(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ProfileEditPage()),
    );
    if (changed == true && mounted) _loadProfile(reset: true);
  }

  /// 点击评论项：进入对应角色卡详情，并定位到该条评论。
  void _openCommentCard(Map<String, dynamic> c) {
    final card = c['card'];
    final cardId = card is Map ? card['id'] : null;
    if (cardId is String && cardId.isNotEmpty) {
      final rawId = c['id'];
      final commentId = rawId is int ? rawId : int.tryParse('$rawId');
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CardDetailPage(
            cardId: cardId,
            focusCommentId: commentId,
          ),
        ),
      );
    }
  }

  String _joinDate(String s) {
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// 他人主页（独立页，带顶栏返回）。
class UserProfilePage extends StatelessWidget {
  const UserProfilePage({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('@$username'),
        centerTitle: true,
      ),
      body: ProfileView(username: username),
    );
  }
}

/// 关注 / 粉丝列表页。
class FollowListPage extends StatefulWidget {
  const FollowListPage({
    super.key,
    required this.username,
    required this.followers,
  });

  final String username;

  /// true=粉丝，false=关注。
  final bool followers;

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final data = widget.followers
          ? await ApiClient.instance.getFollowers(widget.username, page: page)
          : await ApiClient.instance.getFollowing(widget.username, page: page);
      if (!mounted) return;
      final items = data['items'];
      final list = (items is List)
          ? items
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (reset) {
          _users.clear();
          _error = null;
        }
        _users.addAll(list);
        _page = page;
        if (list.isEmpty) _noMore = true;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (_users.isEmpty) _error = '$e';
        });
      }
    }
  }

  void _openUser(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.followers ? '粉丝' : '关注'),
        centerTitle: true,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _users.isEmpty) {
      return ErrorState(onRetry: () => _load(reset: true));
    }
    if (_users.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: '暂无数据',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _load();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _users.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          if (index >= _users.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final u = _users[index];
          final nickname = (u['nickname'] ?? '').toString();
          final username = (u['username'] ?? '').toString();
          return ListTile(
            leading: _Avatar(
              avatar: (u['avatar'] ?? '').toString(),
              radius: 22,
            ),
            title: Text(
              nickname.isEmpty ? username : nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openUser(username),
          );
        },
      ),
    );
  }
}

/// 吸顶 TabBar 的 SliverPersistentHeader 委托。
class _SliverTabBarHeader extends SliverPersistentHeaderDelegate {
  _SliverTabBarHeader({required this.child});

  final Widget child;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 1 : 0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarHeader oldDelegate) =>
      oldDelegate.child != child;
}

/// 个人页评论 tab 的单条评论：内容 + 所属卡片 + 时间，点击进入卡片详情。
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onTap});

  final Map<String, dynamic> comment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = comment['author'];
    final avatar = author is Map ? (author['avatar'] ?? '').toString() : '';
    final content = (comment['content'] ?? '').toString();
    final replyTo = comment['reply_to'];
    final replyName =
        replyTo is Map ? (replyTo['author_name'] ?? '').toString() : '';
    final card = comment['card'];
    final cardName = card is Map ? (card['name'] ?? '').toString() : '';
    final time = formatRelativeTime((comment['created_at'] ?? '').toString());
    return ListTile(
      onTap: onTap,
      leading: Avatar(avatar: avatar, radius: 18),
      title: replyName.isEmpty
          ? StickerText(content, maxLines: 3, overflow: TextOverflow.ellipsis)
          : StickerText('回复 @$replyName：$content',
              maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.article_outlined, size: 14, color: scheme.outline),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                cardName.isEmpty ? '未知卡片' : cardName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当子组件所在的 tab 变为可见（`TabBarView` 会用 `TickerMode` 关闭离屏页的动画）
/// 时，触发一次 [onActive] 回调。
///
/// 用于「切到该 tab 且数据为空」时自动重拉，修复启动阶段登录态未就绪导致请求
/// 401 后残留空态、用户已发布内容却不显示的问题。
class _ReloadOnActive extends StatefulWidget {
  const _ReloadOnActive({required this.onActive, required this.child});

  final VoidCallback onActive;
  final Widget child;

  @override
  State<_ReloadOnActive> createState() => _ReloadOnActiveState();
}

class _ReloadOnActiveState extends State<_ReloadOnActive> {
  bool _wasActive = false;
  bool _pending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive && !_pending) {
      // 延迟到本帧 build 完成后回调，避免在 build 期间触发父级 setState。
      _pending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        if (!mounted || !TickerMode.valuesOf(context).enabled) return;
        widget.onActive();
      });
    }
    _wasActive = active;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

