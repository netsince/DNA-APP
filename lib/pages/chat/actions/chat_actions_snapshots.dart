part of '../../chat_page.dart';

mixin ChatActionsSnapshots on ChatStateMixin {
  Future<List<ChatSnapshot>> _loadSnapshots() async {
    return _snapshotStore.loadSnapshots(_conversation.id);
  }

  Future<void> _saveSnapshots(List<ChatSnapshot> snapshots) async {
    await _snapshotStore.saveSnapshots(_conversation.id, snapshots);
  }

  Future<void> _manageSnapshots() async {
    final List<ChatSnapshot> snapshots = await _loadSnapshots();
    if (!mounted) {
      return;
    }
    final String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: _accentTheme,
          child: AlertDialog(
            title: const FitText('存档管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: snapshots.isEmpty
                ? const FitText('暂无存档')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshots.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatSnapshot snapshot = snapshots[index];
                      final DateTime time = DateTime.fromMillisecondsSinceEpoch(snapshot.timestamp);
                      return ListTile(
                        title: FitText(snapshot.name),
                        subtitle: FitText(time.toString().substring(0, 19)),
                        onTap: () => Navigator.of(context).pop('load:$index'),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const FitText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('create'),
              child: const FitText('新建存档'),
            ),
          ],
        ),
      );
    },
  );
    if (action == null) {
      return;
    }
    if (action == 'create') {
      if (!mounted) return;
      final String defaultName = '存档 ${DateTime.now().toString().substring(0, 19)}';
      final String? name = await showTextInputDialog(
        context: context,
        title: '创建存档',
        hintText: '输入存档名称',
        initialValue: defaultName,
        accentColor: _accent,
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      snapshots.insert(
        0,
        ChatSnapshot(
          id: newId(),
          name: name.trim(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          data: _conversation.toJson(),
        ),
      );
      await _saveSnapshots(snapshots);
      if (!mounted) {
        return;
      }
      showSnack(context, '存档已保存。');
      return;
    }
    if (action.startsWith('load:')) {
      if (!mounted) return;
      final int index = int.tryParse(action.split(':').last) ?? -1;
      if (index < 0 || index >= snapshots.length) {
        return;
      }
      final bool confirmed = await showConfirmDialog(
        context: context,
        title: '确认加载存档',
        content: '将覆盖当前对话并无法撤销，确定要继续吗？',
        accentColor: _accent,
      );
      if (!confirmed) {
        return;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshots[index].data);
      data['id'] = _conversation.id;
      _conversation = Conversation.fromJson(data);
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
  }
}
