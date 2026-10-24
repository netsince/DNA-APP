import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/theme/tokens.dart';

/// 侧边栏 / 底栏导航目标。
enum AppNavTarget {
  recommend,
  worlds,
  teahouse,
  upload,
  imagegen,
  me,
  settings,
}

/// 社区侧边栏内容。
///
/// **一份内容，两种形态**：竖屏是汉堡拉出的抽屉，横屏是常驻左栏（横屏没有底栏，
/// 所以这一份就是唯一导航）。因此这里**不按形态分叉** —— 主导航必须留在里面。
///
/// 结构自上而下，按「用户要干什么」分组，而不是按「东西是什么」：
///
/// 1. 身份块（**吸顶**）：登录态是头像 + 昵称 + @用户名，未登录是登录引导卡；
/// 2. 主导航：推荐 / 茶馆 / 发布 / 生图；
/// 3. 我的（仅登录后）：通知（带未读角标）/ 我的发布 / 我的收藏；
/// 4. 社区：公告 / 官方文章 / 站长推荐 / 赞助；
/// 5. 工具：代理中转（单项不配组标题）；
/// 6. 返回主应用：**固定底部**，不参与滚动。
///
/// ## 为什么「我的」只放三项
///
/// 网页版的「功能菜单」塞了 14 项，是因为它没有第三个归口；客户端还有「我」页
/// （自带 角色卡 / 茶馆 / 评论 三个 tab）。侧边栏是**导航**不是档案柜，
/// 所以我点赞的 / 点数 / 我的工单 / 我的处罚留在「我」页，只把最高频的三项
/// 提到侧栏一层深的位置。
class AppDrawerContent extends StatelessWidget {
  const AppDrawerContent({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onPlusHubTap,
    this.onShowAnnouncement,
    this.onOpenArticles,
    this.onOpenRecommend,
    this.onOpenProxy,
    this.onOpenSponsor,
    this.onOpenNotifications,
    this.onOpenMyCards,
    this.onOpenMyFavorites,
    this.onLogin,
    this.onExitToMainApp,
  });

  final AppNavTarget selected;
  final void Function(AppNavTarget) onSelect;

  /// 「公告」回调（站点公告弹层）。
  final VoidCallback? onShowAnnouncement;

  /// 「官方文章」回调（文章列表页）。
  final VoidCallback? onOpenArticles;

  /// 「站长推荐」回调（站长推荐页）。
  final VoidCallback? onOpenRecommend;

  /// 「代理中转」回调（BYOK 代理配置页）。
  final VoidCallback? onOpenProxy;

  /// 「赞助」回调。
  final VoidCallback? onOpenSponsor;

  /// 「通知」回调（项上带未读角标）。
  final VoidCallback? onOpenNotifications;

  /// 「发布」格子的覆盖回调。
  ///
  /// 传了就走它（打开「＋」三选一枢纽），不再直接切到角色卡发布页 ——
  /// 与底栏「＋」同源，两条入口行为一致。不传保持旧行为。
  final VoidCallback? onPlusHubTap;

  /// 「我的发布」回调。
  final VoidCallback? onOpenMyCards;

  /// 「我的收藏」回调。
  final VoidCallback? onOpenMyFavorites;

  /// 「登录」回调：未登录时侧栏显示登录引导，由外层打开登录表单。
  final VoidCallback? onLogin;

  /// 「返回主应用」回调：岛被嵌进主项目的「社区」栏目时由外层传入。
  final VoidCallback? onExitToMainApp;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool hasMine = AuthSession.instance.isLoggedIn &&
        (onOpenNotifications != null ||
            onOpenMyCards != null ||
            onOpenMyFavorites != null);
    final bool hasCommunity = onShowAnnouncement != null ||
        onOpenArticles != null ||
        onOpenRecommend != null ||
        onOpenSponsor != null;

    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          // ① 身份块吸顶：横屏常驻栏里一滚就丢身份，所以它不参与滚动。
          AppDrawerIdentity(
            selected: selected,
            onSelect: onSelect,
            onLogin: onLogin,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: <Widget>[
                // ② 主导航。横屏靠它，竖屏是快捷切换 —— 一份内容两处都得对。
                _navTile(AppNavTarget.recommend, Icons.home_outlined, '推荐'),
                _navTile(AppNavTarget.worlds, Icons.public_outlined, '世界'),
                _navTile(AppNavTarget.teahouse, Icons.local_cafe_outlined, '茶馆'),
                _navTile(AppNavTarget.upload, Icons.upload_outlined, '发布'),
                _navTile(
                  AppNavTarget.imagegen,
                  Icons.auto_awesome_outlined,
                  '生图',
                ),

                // ③ 我的（仅登录后）。未登录整组隐藏，而不是列一堆点了要登录的项。
                if (hasMine) ...<Widget>[
                  _groupHeader(context, '我的'),
                  if (onOpenNotifications != null)
                    _NotificationTile(onTap: onOpenNotifications!),
                  if (onOpenMyCards != null)
                    _actionTile(
                      Icons.badge_outlined,
                      '我的发布',
                      onOpenMyCards!,
                    ),
                  if (onOpenMyFavorites != null)
                    _actionTile(
                      Icons.bookmark_outline,
                      '我的收藏',
                      onOpenMyFavorites!,
                    ),
                ],

                // ④ 社区
                if (hasCommunity) ...<Widget>[
                  _groupHeader(context, '社区'),
                  if (onShowAnnouncement != null)
                    _actionTile(
                      Icons.campaign_outlined,
                      '公告',
                      onShowAnnouncement!,
                    ),
                  if (onOpenArticles != null)
                    _actionTile(
                      Icons.article_outlined,
                      '官方文章',
                      onOpenArticles!,
                    ),
                  if (onOpenRecommend != null)
                    _actionTile(
                      Icons.recommend_outlined,
                      '站长推荐',
                      onOpenRecommend!,
                    ),
                  if (onOpenSponsor != null)
                    _actionTile(
                      Icons.volunteer_activism_outlined,
                      '赞助',
                      onOpenSponsor!,
                    ),
                ],

                // ⑤ 工具
                if (onOpenProxy != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _actionTile(
                    Icons.alt_route_outlined,
                    '代理中转',
                    onOpenProxy!,
                  ),
                ],
              ],
            ),
          ),
          // ⑥ 离开固定底部：它现在混在滚动流最后，列表一长就找不到，
          //    而且和「公告」只隔一条线 —— 一个是离开、一个是内容。
          if (onExitToMainApp != null)
            AppDrawerExitBar(onTap: onExitToMainApp!),
        ],
      ),
    );
  }

  Widget _navTile(AppNavTarget target, IconData icon, String label) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected == target,
      // 「发布」格子在给了枢纽回调时改走枢纽（与底栏「＋」同源），
      // 其余格子照常导航。
      onTap: (target == AppNavTarget.upload && onPlusHubTap != null)
          ? onPlusHubTap!
          : () => onSelect(target),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }

  /// 组标题。分组靠标题而不是分割线 —— 抽屉里两条 Divider 显得很碎。
  Widget _groupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: AppWeight.medium,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 侧边栏顶部的身份块（吸顶）。
///
/// 登录态：头像 + 昵称 + @用户名，整块可点进「我」。
/// 未登录：一句引导 + 「登录」按钮 —— 否则未登录时整个抽屉几乎是空的。
class AppDrawerIdentity extends StatelessWidget {
  const AppDrawerIdentity({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onLogin,
  });

  final AppNavTarget selected;
  final void Function(AppNavTarget) onSelect;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: AuthSession.instance,
      builder: (BuildContext context, _) {
        final AuthSession session = AuthSession.instance;
        return Container(
          width: double.infinity,
          color: cs.primaryContainer,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                SiteConfig.instance.siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer.withValues(alpha: AppAlpha.muted),
                ),
              ),
              AppSpacing.hSm,
              if (session.isLoggedIn)
                _loggedIn(context, theme, cs, session)
              else
                _guest(theme, cs),
            ],
          ),
        );
      },
    );
  }

  Widget _loggedIn(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AuthSession session,
  ) {
    final String username = (session.user?['username'] ?? '').toString();
    return InkWell(
      onTap: () => onSelect(AppNavTarget.me),
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            Avatar(avatar: session.avatar, radius: 18),
            AppSpacing.wMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    session.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: AppWeight.medium,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer
                            .withValues(alpha: AppAlpha.muted),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _guest(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '登录后可发布角色卡、收藏与评论',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onPrimaryContainer,
          ),
        ),
        AppSpacing.hMd,
        FilledButton(
          onPressed: onLogin,
          child: const Text('登录'),
        ),
      ],
    );
  }
}

/// 「通知」项：带未读角标。
///
/// 未读数自己取一次，**不是每次 rebuild 都请求** —— 横屏时侧栏是常驻的，跟着
/// RootShell 的 setState 反复发请求很难看。取不到就只是没角标，不影响进通知页。
class _NotificationTile extends StatefulWidget {
  const _NotificationTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthSession.instance.isLoggedIn) return;
    try {
      final int unread = await ApiClient.instance.getUnreadNotificationCount();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      // 静默：少一个角标而已。
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      title: const Text('通知'),
      onTap: widget.onTap,
    );
  }
}

/// 侧边栏底部的「返回主应用」：固定，不参与滚动。
///
/// 底色与上面的列表区分开 —— 它是「离开」，不该看起来像又一个内容项。
class AppDrawerExitBar extends StatelessWidget {
  const AppDrawerExitBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.keyboard_return,
                size: AppSize.iconCard,
                color: cs.onSurfaceVariant,
              ),
              AppSpacing.wMd,
              Text(
                '返回主应用',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
