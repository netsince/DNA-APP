import 'package:flutter/material.dart';

import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/server_setup_page.dart';
import 'package:dna/island_app/shutdown_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「社区」栏目：把整体复制进来的「岛」接进主项目的栏目壳。
///
/// 「返回主应用」跳回「主页」：用户的心智是"回到主应用"，而不是
/// "回到上一次所在的栏目"。
///
/// 这里**只做接线，不改岛的功能**：
/// * 岛的启动初始化（读设置、解析服务器地址、拉站点配置与登录会话、预取
///   表情包）搬到了 [CommunityPreload]，由主应用在首屏之后**隐藏预热**；
///   这里只等它，不再自己发起 —— 用户点进来时通常已经就绪，直接见内容；
/// * 服务器没配好时，让岛自己的设置页顶上来；站点关停时让关停页顶上来；
///   其余情况直接渲染岛的 `RootShell`。
///
/// 主题不另起一套：直接用主项目的 Theme，视觉跟「我家/世界」保持一致。
/// 岛自带顶栏/抽屉/底部导航（那是它的功能入口），所以这一栏隐藏主项目
/// 底栏，避免两条底栏叠在一起。
SectionPageData communitySection(AppController controller) {
  return SectionPageData(
    section: AppSection.community,
    // 岛是按整窗宽设计的（自己处理横竖屏分支），不做内容列内缩：
    // 传一个极大的上限，壳的 inset 会被钳到 0（见 _contentInset）。
    contentMaxWidth: double.infinity,
    hideBottomNav: true,
    // 岛自带顶栏（含 推荐/刷一刷/探索 子 tab 与搜索），主项目标题栏让位。
    // 注意：隐藏后该栏目没有主项目的抽屉按钮，退出靠横向滑动或系统返回。
    hideAppBar: true,
    appBar: (BuildContext context) => AppBar(
      title: const FitText('社区'),
    ),
    body: (BuildContext context) => const CommunityBody(),
  );
}

/// 社区内容：等岛的隐藏预热完成，再渲染岛的外壳。
class CommunityBody extends StatefulWidget {
  const CommunityBody({super.key});

  @override
  State<CommunityBody> createState() => _CommunityBodyState();
}

class _CommunityBodyState extends State<CommunityBody> {
  bool _shutdownDismissed = false;

  @override
  void initState() {
    super.initState();
    // 预热通常已经跑完（主应用首屏之后就在后台做了）；没跑完时这里补上，
    // 并等它结束 —— 只有「用户比预热更快点到社区」这一种情况才会看到转圈。
    if (!CommunityPreload.instance.isBooted) {
      CommunityPreload.instance.ensureBooted().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 搬自岛的 `MyApp._onSetupDone()`。
  Future<void> _onSetupDone() async {
    await CommunityPreload.instance.completeSetup();
    if (mounted) setState(() {});
  }

  /// 「返回主应用」：跳回「主页」。
  ///
  /// 刻意在这里（而不是外层闭包）取壳：栏目内容是"胶片"，会被卸载重建，
  /// 外层闭包捕获的 context 在胶片滑走后已失效，maybeOf 会查不到壳 ——
  /// 返回按钮就会变成空操作。这里用的是**当前挂着**的 context。
  void _exitToMainApp() {
    AppSectionShell.maybeOf(context)?.navigateTo(
      AppSection.home,
      axis: Axis.horizontal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CommunityPreload preload = CommunityPreload.instance;
    if (!preload.isBooted) {
      return const Center(child: CircularProgressIndicator());
    }
    if (preload.needsSetup) {
      return ServerSetupPage(
        onDone: _onSetupDone,
        initialError: preload.setupError,
      );
    }
    final SiteConfig site = SiteConfig.instance;
    if (site.shutdownEnabled && !_shutdownDismissed) {
      return ShutdownPage(
        onDismissed: () => setState(() => _shutdownDismissed = true),
      );
    }
    return RootShell(onExitToMainApp: _exitToMainApp);
  }
}
