import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/app_settings.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/server_setup_page.dart';
import 'package:dna/island_app/shutdown_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「社区」栏目：把整体复制进来的「岛」接进主项目的栏目壳。
///
/// 这里**只做接线，不改岛的功能**：
/// * 岛原来靠自己的 `main.dart` 做启动初始化（读设置、解析服务器地址、
///   拉站点配置与登录会话、预取表情包）。现在 `main.dart` 不再是入口，
///   所以把那段初始化原样搬到这里；
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
    appBar: (BuildContext context) => AppBar(
      title: const FitText('社区'),
    ),
    body: (BuildContext context) => const CommunityBody(),
  );
}

/// 社区内容：岛的启动流程 + 岛的外壳。
class CommunityBody extends StatefulWidget {
  const CommunityBody({super.key});

  @override
  State<CommunityBody> createState() => _CommunityBodyState();
}

class _CommunityBodyState extends State<CommunityBody> {
  bool _booting = true;
  bool _needsSetup = false;
  String? _setupError;
  bool _shutdownDismissed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 搬自岛的 `MyApp._init()`：首次启动（尚无地址）时先试官方默认地址，
  /// 校验失败才落到设置页；已配置过的安装不做校验，避免把一次网络抖动
  /// 变成强制设置页。
  Future<void> _init() async {
    await Future.wait(<Future<void>>[
      AppSettings.instance.load(),
      ServerConfig.getBaseUrl(),
    ]);
    if (!ServerConfig.hasBaseUrl) {
      final String? err = await ApiClient.instance.validateServer(
        ServerConfig.defaultBaseUrl,
      );
      if (err == null) {
        await ServerConfig.setBaseUrl(ServerConfig.defaultBaseUrl);
      } else {
        if (!mounted) {
          return;
        }
        setState(() {
          _needsSetup = true;
          _setupError = err;
          _booting = false;
        });
        return;
      }
    }
    await SiteConfig.instance.load();
    await AuthSession.instance.load();
    // 后台预取表情包目录（公开接口），失败静默回退。
    StickerCatalog.instance.ensureLoaded();
    if (mounted) {
      setState(() => _booting = false);
    }
  }

  /// 搬自岛的 `MyApp._onSetupDone()`。
  void _onSetupDone() {
    setState(() {
      _needsSetup = false;
      _setupError = null;
    });
    SiteConfig.instance.load();
    AuthSession.instance.load();
    StickerCatalog.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_needsSetup) {
      return ServerSetupPage(onDone: _onSetupDone, initialError: _setupError);
    }
    final SiteConfig site = SiteConfig.instance;
    if (site.shutdownEnabled && !_shutdownDismissed) {
      return ShutdownPage(
        onDismissed: () => setState(() => _shutdownDismissed = true),
      );
    }
    return const RootShell();
  }
}
