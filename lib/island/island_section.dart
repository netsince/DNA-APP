import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_feed.dart';
import 'island_login_dialog.dart';
import 'island_search_page.dart';
import 'island_session.dart';

/// 「岛」栏目装配：浏览社区里的角色卡。
///
/// **本地为主**：这一栏只读社区内容（探索 / 搜索），点进去可以**试聊**或
/// **导入到我家**；没有登录也能浏览与导入，只有「发布到岛」需要账号 ——
/// 所以这里不做任何启动引导，账号入口只是一个可点的图标。
SectionPageData islandSection(AppController controller) {
  // 登录态不是 ValueNotifier（它是静态会话），这里用一个本地开关驱动标题栏
  // 图标刷新：登录/退出后手动翻一下，避免整栏重建。
  final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(
    IslandSession.isLoggedIn,
  );

  Future<void> openSearch(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            IslandSearchPage(controller: controller),
      ),
    );
  }

  Future<void> openAccount(BuildContext context) async {
    if (!IslandSession.isLoggedIn) {
      final bool ok = await showIslandLoginDialog(context);
      if (ok) {
        loggedIn.value = true;
      }
      return;
    }
    final bool? logout = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const FitText('岛账号'),
        content: FitText('已登录：${IslandSession.displayName}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const FitText('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const FitText('退出登录'),
          ),
        ],
      ),
    );
    if (logout == true) {
      await IslandSession.logout();
      loggedIn.value = false;
    }
  }

  return SectionPageData(
    section: AppSection.island,
    // 卡片墙：和「我家」用同一个内容列宽，桌面才排得开列。
    contentMaxWidth: AppSize.cardGridMaxWidth,
    appBar: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: loggedIn,
      builder: (BuildContext context, bool logged, Widget? _) => AppBar(
        title: const FitText('岛'),
        actions: <Widget>[
          IconButton(
            tooltip: '搜索角色卡',
            onPressed: () => openSearch(context),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: logged ? '岛账号' : '登录岛账号',
            onPressed: () => openAccount(context),
            icon: Icon(
              logged ? Icons.account_circle : Icons.account_circle_outlined,
            ),
          ),
        ],
      ),
    ),
    body: (BuildContext context) => IslandFeedBody(controller: controller),
  );
}
