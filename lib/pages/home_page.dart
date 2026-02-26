import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/role.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'chat_page.dart';
import 'conversation_create_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> conversations = controller.conversations;
        return Scaffold(
          appBar: AppBar(
            title: const Text('消息'),
            actions: <Widget>[
              IconButton(
                tooltip: '新建会话',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => ConversationCreatePage(controller: controller),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          drawer: AppDrawer(controller: controller, current: AppSection.home),
          body: conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('还没有会话，点击右上角 + 新建。'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => ConversationCreatePage(controller: controller),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('新建会话'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: conversations.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Conversation conversation = conversations[index];
                    final Role? role = controller.getRoleById(conversation.roleId);
                    final World? world = controller.getWorldById(conversation.worldId);
                    final String title = conversation.note.isNotEmpty
                        ? conversation.note
                        : (role?.name.isNotEmpty == true ? role!.name : '未命名会话');
                    final String subtitle = world == null
                        ? '角色：${role?.name.isNotEmpty == true ? role!.name : '未命名角色'}'
                        : '角色：${role?.name.isNotEmpty == true ? role!.name : '未命名角色'} · 世界：${world.name}';
                    return Card(
                      child: ListTile(
                        title: Text(title),
                        subtitle: Text(subtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => ChatPage(
                                controller: controller,
                                conversationId: conversation.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
