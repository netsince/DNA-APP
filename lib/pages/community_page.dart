import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dna/island_app/card_publish_source.dart';
import 'package:dna/island_app/ta_import_sink.dart';
import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/server_setup_page.dart';
import 'package:dna/island_app/shutdown_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/utils/id_utils.dart';
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
    // 只是被"路过"时**不要**挂载岛的外壳：岛一挂载就会弹站点公告、弹各种
    // SnackBar、还会构建一大堆岛内页面 —— 这些副作用不该发生在主应用里
    // （详见 SectionPageData.mountWhenPassing）。只有真正进入社区才挂载。
    mountWhenPassing: false,
    appBar: (BuildContext context) => AppBar(
      title: const FitText('社区'),
    ),
    body: (BuildContext context) => CommunityBody(controller: controller),
  );
}

/// 主应用侧的「导入世界」落地。
///
/// 社区只认 [WorldImportSink] 这一个方法，不认 AppController —— 社区对主应用
/// 是零状态依赖（只 import 两个 widget），这个边界值得守。
class _MainAppWorldBridge implements WorldImportSink, WorldPublishSource {
  _MainAppWorldBridge(this.controller);

  final AppController controller;

  /// 发布页用：只列**未归档**的世界（归档的不该再被发到社区）。
  @override
  List<World> localWorlds() => controller.activeWorlds;

  @override
  Future<String> importWorld(World world) async {
    // **必须换 id**：本地世界的 id 由客户端 newId() 生成，社区世界的 id 是
    // 后端分配的 UUID，两套 id 直接混用会撞（本地已有同 id 的世界会被覆盖）。
    final World local = world.copyWith(id: newId());
    await controller.upsertWorld(local);
    return local.id;
  }
}

/// 主应用侧的「导入社区角色卡」落地。
///
/// **必须换 id**：本地卡的 id 由客户端生成，社区卡是后端 UUID，
/// 直接用会把本地同名卡覆盖掉。
class _MainAppTaImportBridge implements TaImportSink {
  _MainAppTaImportBridge(this.controller);

  final AppController controller;

  @override
  Future<String> importTa(TA ta) async {
    final TA local = ta.copyWith(id: newId());
    await controller.upsertTa(local);
    return local.id;
  }
}

/// 主应用侧的「取本地角色卡」落地（发布角色卡用）。
///
/// 与 [_MainAppWorldBridge] 同一个思路：只注入社区需要的两个方法，不传
/// AppController。
class _MainAppCardBridge implements CardPublishSource {
  _MainAppCardBridge(this.controller);

  final AppController controller;

  /// 只列**未归档**的角色卡（归档的不该再被发到社区）。
  @override
  List<TA> localCards() => controller.activeTas;

  /// 发布要的是 base64，社区拿不到本地文件，只能请主应用代读。
  @override
  Future<Uint8List?> imageBytes(String ref) =>
      ImageStorage.instance.readBytes(ref);
}

/// 社区内容：等岛的隐藏预热完成，再渲染岛的外壳。
class CommunityBody extends StatefulWidget {
  const CommunityBody({super.key, required this.controller});

  /// 用来读「返回主应用按钮」这个开关；监听它，改了设置立刻生效。
  final AppController controller;

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
    // 岛内所有提示（SnackBar）都走 `ScaffoldMessenger.of(context)`。主项目根部
    // 的那个 messenger 会把它们画到**主应用**的 Scaffold 上：人已经离开社区了，
    // 提示还挂在主应用底部（用户反馈「提示框有一定概率一直常驻不消失」）。
    //
    // 给社区单开一个 messenger：提示只属于社区，社区一卸载就跟着消失。
    // 社区是全屏栏目，视觉位置与原来一致（还是屏幕底部）。
    return ScaffoldMessenger(child: _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) => RootShell(
        // 设置里关掉「返回主应用」就传 null：顶栏那个按钮和侧边栏底部的
        // 条目都跟着消失（两处都是 onExitToMainApp != null 才渲染）。
        onExitToMainApp: widget.controller.settings.showExitToMainApp
            ? _exitToMainApp
            : null,
        worldImportSink: _MainAppWorldBridge(widget.controller),
        worldPublishSource: _MainAppWorldBridge(widget.controller),
        cardPublishSource: _MainAppCardBridge(widget.controller),
        taImportSink: _MainAppTaImportBridge(widget.controller),
      ),
    );
  }
}
