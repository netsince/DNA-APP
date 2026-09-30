import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/widgets/refreshable.dart';

/// 工单状态标签映射。
String ticketStatusLabel(String status) => switch (status) {
      'open' => '待处理',
      'replied' => '已回复',
      'closed' => '已关闭',
      _ => '待处理',
    };

/// 我的工单入口页：列表 + 状态筛选 + 新建。
class TicketsPage extends StatefulWidget {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  final List<Map<String, dynamic>> _tickets = <Map<String, dynamic>>[];
  String _status = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final r = await ApiClient.instance.getMyTickets(
          page: reset ? 1 : _page + 1, status: _status);
      if (!mounted) return;
      setState(() {
        if (reset) _tickets.clear();
        _tickets.addAll(r.items);
        _page = reset ? 1 : _page + 1;
        _noMore = r.items.isEmpty || !r.hasNext;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _setStatus(String s) {
    setState(() {
      _status = s;
      _page = 0;
      _noMore = false;
      _tickets.clear();
    });
    _load(reset: true);
  }

  Future<void> _openDetail(Map<String, dynamic> t) async {
    final id = (t['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TicketDetailPage(ticketId: id)),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _openNew() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewTicketPage()),
    );
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的工单'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('新建工单'),
      ),
      body: Column(
        children: <Widget>[
          _statusBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading && _tickets.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _tickets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.support_agent,
                                size: 40, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text('暂无工单',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : AppRefreshIndicator(
                        onRefresh: () => _load(reset: true),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels >=
                                n.metrics.maxScrollExtent - 400) {
                              _load();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _tickets.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _tickets.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                );
                              }
                              return _ticketTile(_tickets[index]);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    const statuses = <(String, String)>[
      ('all', '全部'),
      ('open', '待处理'),
      ('replied', '已回复'),
      ('closed', '已关闭'),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: statuses.map((s) {
          final selected = _status == s.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(s.$2),
              selected: selected,
              onSelected: (_) => _setStatus(s.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _ticketTile(Map<String, dynamic> t) {
    final scheme = Theme.of(context).colorScheme;
    final status = (t['status'] ?? 'open').toString();
    final title = (t['title'] ?? '').toString();
    final preview = (t['last_message'] is Map)
        ? (t['last_message']['content'] ?? '').toString()
        : (t['content'] ?? '').toString();
    final updated = (t['updated_at'] ?? '').toString();

    final Color? chipBg = switch (status) {
      'open' => scheme.tertiaryContainer,
      'replied' => scheme.primaryContainer,
      'closed' => scheme.surfaceContainerHighest,
      _ => null,
    };
    final Color? chipFg = switch (status) {
      'open' => scheme.onTertiaryContainer,
      'replied' => scheme.onPrimaryContainer,
      'closed' => scheme.onSurfaceVariant,
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (preview.isNotEmpty)
              Text(preview,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(ticketStatusLabel(status),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: chipFg)),
                ),
                const Spacer(),
                Text(_fmtDate(updated),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetail(t),
      ),
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

/// 新建工单页。
class NewTicketPage extends StatefulWidget {
  const NewTicketPage({super.key});

  @override
  State<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<NewTicketPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  List<Map<String, dynamic>> _categories = const <Map<String, dynamic>>[];
  int? _categoryId;
  XFile? _image;
  bool _submitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiClient.instance.getTicketCategories();
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {
      // 类别加载失败不阻塞，用户仍可新建（category 可选）。
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (!mounted) return;
      setState(() => _image = picked);
    } catch (_) {
      if (!mounted) return;
      _snack('选择图片失败');
    }
  }

  String? _mimeOf(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'png':
      default:
        return 'image/png';
    }
  }

  Future<String?> _readImage() async {
    final file = _image;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'png';
      return 'data:${_mimeOf(ext)};base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!AuthSession.instance.isLoggedIn) {
      _snack('请先登录');
      return;
    }
    setState(() => _submitting = true);
    try {
      final image = await _readImage();
      await ApiClient.instance.createTicket(
        title: _title.text.trim(),
        content: _content.text.trim(),
        categoryId: _categoryId,
        imageData: image,
      );
      if (!mounted) return;
      _snack('工单已提交，请等待管理员回复');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建工单'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _submitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(onPressed: _submit, child: const Text('提交')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_categories.isNotEmpty) ...<Widget>[
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: '分类（可选）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem<int>(
                      value: (c['id'] as num?)?.toInt(),
                      child: Text((c['name'] ?? '').toString()),
                    ),
                ],
                onChanged: (v) => _categoryId = v,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _title,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写工单主题' : null,
              decoration: const InputDecoration(
                labelText: '主题 *',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _content,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '问题描述',
                hintText: '请详细描述你遇到的问题（也可只传图）',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (_image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_image!.path),
                        width: 80, height: 80, fit: BoxFit.cover),
                  ),
                if (_image != null) const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_image != null ? '更换图片' : '添加图片（可选）'),
                ),
                if (_image != null)
                  TextButton(
                    onPressed: () => setState(() => _image = null),
                    child: const Text('移除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 工单详情页：对话 + 回复 + 关闭/重开。
class TicketDetailPage extends StatefulWidget {
  const TicketDetailPage({super.key, required this.ticketId});

  final int ticketId;

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  final _replyController = TextEditingController();
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];
  bool _loading = true;
  bool _sending = false;
  XFile? _image;
  final ImagePicker _picker = ImagePicker();

  bool get _closed => (_ticket?['status'] ?? 'open').toString() == 'closed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiClient.instance.getTicketDetail(widget.ticketId);
      if (!mounted) return;
      final messages = d['messages'];
      setState(() {
        _ticket = d;
        _messages = messages is List
            ? messages
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
            : <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('加载失败：$e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (!mounted) return;
      setState(() => _image = picked);
    } catch (_) {
      if (!mounted) return;
      _snack('选择图片失败');
    }
  }

  String? _mimeOf(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'png':
      default:
        return 'image/png';
    }
  }

  Future<String?> _readImage() async {
    final file = _image;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'png';
      return 'data:${_mimeOf(ext)};base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    final image = await _readImage();
    if (content.isEmpty && image == null) {
      _snack('请填写回复内容或上传图片');
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiClient.instance.replyTicket(widget.ticketId,
          content: content, imageData: image);
      if (!mounted) return;
      _replyController.clear();
      setState(() => _image = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('回复失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    try {
      await ApiClient.instance.closeTicket(widget.ticketId);
      if (!mounted) return;
      _snack('工单已关闭');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('操作失败：$e');
    }
  }

  Future<void> _reopen() async {
    try {
      await ApiClient.instance.reopenTicket(widget.ticketId);
      if (!mounted) return;
      _snack('工单已重新打开');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('操作失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (_ticket?['title'] ?? '').toString();
    final status = (_ticket?['status'] ?? 'open').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? '工单详情' : title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: switch (status) {
                    'replied' => scheme.primaryContainer,
                    'closed' => scheme.surfaceContainerHighest,
                    _ => scheme.tertiaryContainer,
                  },
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(ticketStatusLabel(status),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                if (_closed)
                  Container(
                    width: double.infinity,
                    color: scheme.surfaceContainerHighest,
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text('此工单已关闭',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _reopen,
                          child: const Text('重新打开'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(child: Text('暂无消息'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _messageBubble(_messages[index]),
                        ),
                ),
                if (!_closed)
                  _replyBar(),
              ],
            ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final scheme = Theme.of(context).colorScheme;
    final role = (m['sender_role'] ?? 'user').toString();
    final isUser = role == 'user';
    final content = (m['content'] ?? '').toString();
    final sender = (m['sender_name'] ?? '').toString();
    final created = (m['created_at'] ?? '').toString();
    final time = created.length >= 16
        ? created.substring(0, 16)
        : created;
    final image = (m['image'] ?? '').toString();

    final bubbleColor = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isUser
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isUser ? '我' : (sender.isEmpty ? '管理员' : sender),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            if (content.isNotEmpty)
              Text(content, style: TextStyle(color: textColor)),
            if (image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _TicketImage(image: image),
                ),
              ),
            const SizedBox(height: 4),
            Text(time,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _replyBar() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              onPressed: _pickImage,
              icon: _image != null
                  ? Badge(
                      label: Text('1'),
                      child: const Icon(Icons.image_outlined),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              tooltip: '添加图片',
            ),
            Expanded(
              child: TextField(
                controller: _replyController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '回复…',
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _sending ? null : _sendReply,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              tooltip: '发送',
            ),
            IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close_fullscreen_outlined),
              tooltip: '关闭工单',
            ),
          ],
        ),
      ),
    );
  }
}

/// 工单消息内嵌图片（data URL 或服务器路径）。
class _TicketImage extends StatelessWidget {
  const _TicketImage({required this.image});
  final String image;

  @override
  Widget build(BuildContext context) {
    if (image.startsWith('data:')) {
      try {
        return Image.memory(
          base64Decode(image.split(',').last),
          width: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
              width: 180, height: 120, child: Icon(Icons.broken_image)),
        );
      } catch (_) {
        return const SizedBox(
            width: 180, height: 120, child: Icon(Icons.broken_image));
      }
    }
    // 服务器相对路径（目前后端返回的是 data URL，这里作兜底）。
    return const SizedBox(
        width: 180, height: 120, child: Icon(Icons.image_outlined));
  }
}
