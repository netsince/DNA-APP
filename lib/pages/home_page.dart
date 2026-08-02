import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/app_controller.dart';
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

  Future<void> _toggleArchived() async {
    final bool willShowArchived = !_showArchived;

    // 如果要显示归档且需要验证
    if (willShowArchived && widget.controller.settings.requireAuthForArchive) {
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
