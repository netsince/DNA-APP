import 'package:flutter/material.dart';
import 'package:dna/island_app/site_config.dart';

/// 侧边栏 / 底栏导航目标。
enum AppNavTarget {
  recommend,
  teahouse,
  upload,
  imagegen,
  me,
  settings,
}

/// 共享侧边栏内容：由 [RootShell] 在横屏常驻或汉堡抽屉中复用。
/// 点击条目通过回调切换页面，保证固定侧边栏在首页/设置间始终存在。
class AppDrawerContent extends StatelessWidget {
  const AppDrawerContent({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onShowAnnouncement,
    this.onOpenArticles,
    this.onOpenRecommend,
    this.onOpenProxy,
    this.onOpenSponsor,
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

  /// 「赞助」回调（赞助页）。岛设置并入主项目设置后，赞助从抽屉直达。
  final VoidCallback? onOpenSponsor;

  /// 「返回主应用」回调：岛被嵌进主项目的「社区」栏目时由外层传入；
  /// 岛单独运行时不传，抽屉里不出现该条目。
  final VoidCallback? onExitToMainApp;

  @override
  Widget build(BuildContext context) {
    final cfg = SiteConfig.instance;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  'DNAIsland APP',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  cfg.siteName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _navTile(AppNavTarget.recommend, Icons.home_outlined, '推荐'),
          _navTile(AppNavTarget.teahouse, Icons.local_cafe_outlined, '茶馆'),
          _navTile(AppNavTarget.upload, Icons.upload_outlined, '上传'),
          _navTile(AppNavTarget.imagegen, Icons.auto_awesome_outlined, '生图'),
          _navTile(AppNavTarget.me, Icons.person_outline, '我'),
          if (onOpenSponsor != null) ...<Widget>[
            const Divider(),
            _actionTile(
              Icons.volunteer_activism_outlined,
              '赞助',
              onOpenSponsor!,
            ),
          ],
          if (onShowAnnouncement != null ||
              onOpenArticles != null ||
              onOpenRecommend != null ||
              onOpenProxy != null) ...<Widget>[
            const Divider(),
            if (onOpenProxy != null)
              _actionTile(
                Icons.alt_route_outlined,
                '代理中转',
                onOpenProxy!,
              ),
            if (onShowAnnouncement != null)
              _actionTile(
                Icons.campaign_outlined,
                '公告',
                onShowAnnouncement!,
              ),
            if (onOpenArticles != null)
              _actionTile(Icons.article_outlined, '官方文章', onOpenArticles!),
            if (onOpenRecommend != null)
              _actionTile(Icons.recommend_outlined, '站长推荐', onOpenRecommend!),
          ],
          if (onExitToMainApp != null) ...<Widget>[
            const Divider(),
            _actionTile(
              Icons.keyboard_return,
              '返回主应用',
              onExitToMainApp!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _navTile(AppNavTarget target, IconData icon, String label) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected == target,
      onTap: () => onSelect(target),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}
