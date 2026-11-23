import 'dart:convert';
import '../widgets/memo_image.dart';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/widgets/wide_body.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/widgets/paged_list_body.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';
import '../widgets/submit_form.dart';
import '../theme/tokens.dart';

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
  /// 工单列表的分页状态（首屏 / 加载更多 / 没有更多 / 错误）统一由
  /// [PagedController] 管，本页只提供「怎么取一页」。
  ///
  /// 接口返回的是**记录类型**（items / page / pages / total / hasNext），
  /// 交给类型推断，不自造类型名。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final result = await ApiClient.instance.getMyTickets(
            page: page,
            status: _status,
          );
          return PagedResult<Map<String, dynamic>>(
            items: result.items,
            hasMore: result.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '工单列表加载失败，请稍后重试',
      );

  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _paged.refresh();
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  void _setStatus(String s) {
    setState(() => _status = s);
    // 换了状态筛选，旧结果立即作废：控制器「失败不清列表」是给翻页用的，
    // 这里必须清掉，否则新筛选失败会把上一个状态的工单留在屏幕上。
    _paged.items.clear();
    _paged.refresh();
  }

  Future<void> _openDetail(Map<String, dynamic> t) async {
    final id = (t['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TicketDetailPage(ticketId: id)),
    );
    if (mounted) _paged.refresh();
  }

  Future<void> _openNew() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const NewTicketPage()));
    if (mounted) _paged.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的工单')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('新建工单'),
      ),
      body: Column(
        children: <Widget>[
          _statusBar(),
          const Divider(height: 1),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  /// 列表区：加载中 / 失败（可重试）/ 空 / 有数据，四态分开。
  ///
  /// 失败必须与「暂无工单」分开：以前请求失败只复位 loading，用户看到的是
  /// 「你没有工单」这个错误结论，而且没有任何恢复路径。
  Widget _buildList(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 五态 + 下拉刷新 + 触底加载交给 PagedListBody（原先这里手写 58 行）。
    return PagedListBody<Map<String, dynamic>>(
      controller: _paged,
      padding: EdgeInsets.zero,
      separator: (_, _) => const Divider(height: 1, indent: AppSpacing.lg),
      empty: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.support_agent,
              size: AppSize.iconEmptyCompact,
              // 空态图标用 outline：不抢正文、又是语义色（审计 4.4）。
              color: scheme.outline,
            ),
            const SizedBox(height: 8),
            Text('暂无工单', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
      itemBuilder: (BuildContext context, int index) =>
          _ticketTile(_paged.items[index]),
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

    // 裸 ListTile：工单列表是结构同构、需要线性扫读的集合，
    // 每行一张卡只会把「一屏能看几条」换成「一屏几个框」（审计 3.3）。
    return ListTile(
      contentPadding: AppInsets.tile,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (preview.isNotEmpty)
            Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  ticketStatusLabel(status),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: chipFg),
                ),
              ),
              const Spacer(),
              Text(
                _fmtDate(updated),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openDetail(t),
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
  // 两个文本字段的控制器统一由草稿持有（页面不再各 new 一个）。
  final FormDraft _draft = FormDraft(
    textFields: const <String>['title', 'content'],
  );

  // 一次性提交的忙态 + 失败原因（原因就地显示，不再只弹一句 snackbar）。
  final SubmitFormState _submit = SubmitFormState();

  List<Map<String, dynamic>> _categories = const <Map<String, dynamic>>[];
  int? _categoryId;
  XFile? _image;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 提交态变了就重建：顶栏按钮转圈 / 顶部横幅出现或消失。
    _submit.addListener(_onSubmitChanged);
    _loadCategories();
  }

  /// 提交态（忙 / 失败原因）变了就重建。
  void _onSubmitChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 只摘监听、不 dispose _submit：提交请求可能在页面 pop 之后才回来，
    // 那时 run() 还会 notifyListeners()。
    _submit.removeListener(_onSubmitChanged);
    _draft.dispose();
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
    } catch (e) {
      if (!mounted) return;
      _snack('选择图片失败：${describeError(e)}');
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

  Future<void> _onSubmit() async {
    // 必填校验落在「主题」字段上（文案与时机同原来的 Form validator）。
    if (!_draft.validateRequired(const <(String, String)>[
      ('title', '请填写工单主题'),
    ])) {
      setState(() {});
      return;
    }
    if (!AuthSession.instance.isLoggedIn) {
      _snack('请先登录');
      return;
    }
    await _submit.run(
      errorPrefix: '提交失败',
      action: () async {
        final image = await _readImage();
        await ApiClient.instance.createTicket(
          title: _draft.text('title'),
          content: _draft.text('content'),
          categoryId: _categoryId,
          imageData: image,
        );
        if (!mounted) return;
        _snack('工单已提交，请等待管理员回复');
        Navigator.of(context).pop(true);
      },
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    showSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建工单'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            // 忙时禁用并转圈（占位尺寸不变，按钮不跳）。
            child: FormSubmitButton(
              label: '提交',
              busy: _submit.busy,
              onPressed: _onSubmit,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: AppInsets.card,
        children: <Widget>[
          // 提交失败的真实原因就地显示（不再只弹一句「提交失败」）。
          FormErrorBanner(
            message: _submit.errorText,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
          ),
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
          FormTextField(
            draft: _draft,
            id: 'title',
            label: '主题 *',
            isDense: true,
            border: const OutlineInputBorder(),
            // 一输入就把该字段的必填错误清掉（重建归页面）。
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // 问题描述保留原 TextFormField：多行标签靠 alignLabelWithHint 顶到
          // 首行，共享的 FormTextField 没有透传这个参数，换过去标签会回到垂直
          // 居中（观感变化），所以只把控制器换成草稿里的那一个。
          TextFormField(
            controller: _draft.controller('content'),
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
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Image.file(
                    File(_image!.path),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
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
    } catch (e) {
      if (!mounted) return;
      _snack('选择图片失败：${describeError(e)}');
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
      await ApiClient.instance.replyTicket(
        widget.ticketId,
        content: content,
        imageData: image,
      );
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
    showSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (_ticket?['title'] ?? '').toString();
    final status = (_ticket?['status'] ?? 'open').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.isEmpty ? '工单详情' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: switch (status) {
                    'replied' => scheme.primaryContainer,
                    'closed' => scheme.surfaceContainerHighest,
                    _ => scheme.tertiaryContainer,
                  },
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  ticketStatusLabel(status),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '此工单已关闭',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
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
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _messageBubble(_messages[index]),
                        ),
                ),
                if (!_closed) _replyBar(),
              ],
            ),
    );
  }

  /// 气泡最大宽度：窄屏取屏宽 78%，宽屏按阅读宽度封顶。
  double _bubbleMaxWidth(BuildContext context) {
    final double screen = MediaQuery.sizeOf(context).width;
    final double reading = WideContent.reading.maxWidth;
    final double byScreen = screen * 0.78;
    return byScreen < reading ? byScreen : reading;
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final scheme = Theme.of(context).colorScheme;
    final role = (m['sender_role'] ?? 'user').toString();
    final isUser = role == 'user';
    final content = (m['content'] ?? '').toString();
    final sender = (m['sender_name'] ?? '').toString();
    final created = (m['created_at'] ?? '').toString();
    final time = created.length >= 16 ? created.substring(0, 16) : created;
    final image = (m['image'] ?? '').toString();

    final bubbleColor = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          // 屏宽 78% 只在窄屏成立；宽屏下要按阅读宽度封顶，
          // 否则 1920 宽时一行近百字（审计 3.4）。
          maxWidth: _bubbleMaxWidth(context),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isUser ? '我' : (sender.isEmpty ? '管理员' : sender),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            if (content.isNotEmpty)
              Text(content, style: TextStyle(color: textColor)),
            if (image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: _TicketImage(image: image),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: AppFontSize.tiny,
              ),
            ),
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
        padding: const EdgeInsets.all(AppSpacing.sm),
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
      final int target =
          (180 * MediaQuery.devicePixelRatioOf(context)).clamp(180, 720).round();
      final ImageProvider? provider =
          MemoImage.dataUrl(image, cacheWidth: target);
      if (provider == null) {
        return const SizedBox(
          width: 180,
          height: 120,
          child: Icon(Icons.broken_image),
        );
      }
      return Image(
        image: provider,
        width: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 180,
          height: 120,
          child: Icon(Icons.broken_image),
        ),
      );
    }
    // 服务器相对路径（目前后端返回的是 data URL，这里作兜底）。
    return const SizedBox(
      width: 180,
      height: 120,
      child: Icon(Icons.image_outlined),
    );
  }
}
