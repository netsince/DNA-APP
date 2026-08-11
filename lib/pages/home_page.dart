import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/app_controller.dart';
import '../utils/platform_capabilities.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_drawer.dart';
import 'conversation_create_page.dart';
import 'search_page.dart';
import 'home/home_widgets.dart';
import 'package:dna/widgets/fit_text.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showArchived = false;
  bool _archiveAuthPassed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // 网页版每次进入首页时展示预览提示（从底部弹出）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWebNotice();
      });
    }
  }

  void _showWebNotice() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.info_outline, color: Theme.of(sheetContext).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: FitText('欢迎使用网页版（预览版）', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 16),
              const _WebNoticeItem(
                icon: Icons.cloud_upload_outlined,
                title: '请手动备份数据',
                detail: '网页版数据保存在浏览器中，清理浏览器数据会导致数据丢失。建议在「设置 → 数据管理 → 导出全部数据」中定期手动备份。',
              ),
              const SizedBox(height: 12),
              const _WebNoticeItem(
                icon: Icons.block_outlined,
                title: '部分功能已禁用',
                detail: '语音输入、语音合成、生物识别锁定等功能在网页版中不可用。',
              ),
              const SizedBox(height: 12),
              const _WebNoticeItem(
                icon: Icons.science_outlined,
                title: '预览版',
                detail: '当前为预览版本，功能与体验可能仍在调整，请以实际使用为准。',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const FitText('我知道了'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleArchived() async {
    final bool willShowArchived = !_showArchived;

    // 如果要显示归档且需要验证（Web 端不支持生物识别，跳过验证）
    if (willShowArchived &&
        PlatformCapabilities.biometricAuthSupported &&
        widget.controller.settings.requireAuthForArchive) {
      if (!_archiveAuthPassed) {
        final bool authenticated = await AuthService.authenticateForArchive();
        if (!authenticated) {
          if (mounted) {
            showSnack(context, '验证失败，无法查看归档');
          }
          return;
        }
        _archiveAuthPassed = true;
      }
    }

    setState(() => _showArchived = willShowArchived);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当离开归档页面时重置验证状态
    if (!_showArchived) {
      _archiveAuthPassed = false;
    }
  }

  void _createConversation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ConversationCreatePage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      controller: widget.controller,
      current: AppSection.home,
      appBar: AppBar(
        title: FitText(_showArchived ? '归档' : '消息'),
        actions: <Widget>[
          IconButton(
            tooltip: '搜索',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      SearchPage(controller: widget.controller),
                ),
              );
            },
            icon: const Icon(Icons.search_outlined),
          ),
          IconButton(
            tooltip: _showArchived ? '查看消息' : '查看归档',
            onPressed: _toggleArchived,
            icon: Icon(_showArchived ? Icons.chat_bubble_outline : Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新建会话',
            onPressed: _createConversation,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ConversationListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateConversation: _createConversation,
      ),
      bottomNavigationBar: widget.controller.settings.showBottomNav
          ? AppBottomNav(controller: widget.controller, current: AppSection.home)
          : null,
    );
  }
}

/// 网页版预览提示中的单条说明。
class _WebNoticeItem extends StatelessWidget {
  const _WebNoticeItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FitText(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FitText(detail, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
