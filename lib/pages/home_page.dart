import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/app_controller.dart';
import '../utils/platform_capabilities.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_container.dart';
import '../widgets/app_section.dart';
import 'conversation_create_page.dart';
import 'search_page.dart';
import 'home/home_widgets.dart';
import 'package:dna/widgets/fit_text.dart';

/// 首页(消息)栏目装配。
///
/// 状态(归档开关、生物验证通过标记)住在装配闭包里,随壳常驻:
/// 标题栏动作与内容区通过同一份 [ValueNotifier] 联动。
SectionPageData homeSection(AppController controller) {
  final ValueNotifier<bool> showArchived = ValueNotifier<bool>(false);
  bool archiveAuthPassed = false;

  Future<void> toggleArchived(BuildContext context) async {
    final bool willShowArchived = !showArchived.value;

    // 如果要显示归档且需要验证（Web 端不支持生物识别，跳过验证）
    if (willShowArchived &&
        PlatformCapabilities.biometricAuthSupported &&
        controller.settings.requireAuthForArchive &&
        !archiveAuthPassed) {
      final bool authenticated = await AuthService.authenticateForArchive();
      if (!authenticated) {
        if (context.mounted) {
          showSnack(context, '验证失败，无法查看归档');
        }
        return;
      }
      archiveAuthPassed = true;
    }
    showArchived.value = willShowArchived;
  }

  void createConversation(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ConversationCreatePage(controller: controller),
      ),
    );
  }

  return SectionPageData(
    section: AppSection.home,
    showArchived: showArchived,
    appBar: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => AppBar(
        title: FitText(archived ? '归档' : '消息'),
        actions: <Widget>[
          // 搜索页 / 新建会话页:从图标位置放大,返回时缩回。
          AppBarIconAction<bool>(
            tooltip: '搜索',
            icon: Icons.search_outlined,
            pageBuilder: (BuildContext context) =>
                SearchPage(controller: controller),
          ),
          IconButton(
            tooltip: archived ? '查看消息' : '查看归档',
            onPressed: () => toggleArchived(context),
            icon: Icon(
              archived ? Icons.chat_bubble_outline : Icons.archive_outlined,
            ),
          ),
          AppBarIconAction<bool>(
            tooltip: '新建会话',
            icon: Icons.add,
            pageBuilder: (BuildContext context) =>
                ConversationCreatePage(controller: controller),
          ),
        ],
      ),
    ),
    body: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) =>
          ConversationListBody(
            controller: controller,
            showArchived: archived,
            onCreateConversation: () => createConversation(context),
          ),
    ),
  );
}
