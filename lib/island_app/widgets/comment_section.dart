import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/models/comment.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/user_badge.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';

/// 评论列表加载（GET /cards/`id`/comments）。
typedef CommentLoader = Future<CommentPage> Function(
  String cardId, {
  int page,
  String sort,
  bool onlyAuthor,
});

/// 发表评论（POST /cards/`id`/comments）。
typedef CommentPoster = Future<int> Function(
  String cardId,
  String content, {
  int? replyToId,
  String? imageData,
});

/// 评论点赞/取消。
typedef CommentLiker = Future<({bool liked, int count})> Function(
  String cardId,
  int commentId,
);

/// 评论置顶/取消（仅卡作者）。
typedef CommentPinner = Future<bool> Function(String cardId, int commentId);

/// 删除评论（仅评论作者）。
typedef CommentDeleter = Future<void> Function(String cardId, int commentId);

/// 角色的评论区：列表 / 排序（最新·最热）/ 只看作者 / 发表 / 楼中楼回复 /
/// 点赞 / 置顶（作者）/ 删除（本人），对齐网页版评论抽屉能力。
///
/// 自身管理分页与交互状态；未登录时点赞/发帖会被拦截并提示。
class CommentSection extends StatefulWidget {
  const CommentSection({
    super.key,
    required this.cardId,
    this.focusCommentId,
    this.isLoggedIn,
    this.isOwner,
    this.commentLoader,
    this.commentPoster,
    this.commentLiker,
    this.commentPinner,
    this.commentDeleter,
  });

  final String cardId;

  /// 需要定位并高亮的评论 id（从用户主页点击评论进入时传入）。
  final int? focusCommentId;
  final bool? isLoggedIn;
  final bool? isOwner;
  final CommentLoader? commentLoader;
  final CommentPoster? commentPoster;
  final CommentLiker? commentLiker;
  final CommentPinner? commentPinner;
  final CommentDeleter? commentDeleter;

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  List<Comment> _items = const <Comment>[];
  int _page = 1;
  int _total = 0;
  bool _hasNext = false;
  String _sort = 'latest';
  bool _onlyAuthor = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _posting = false;
  String? _error;
  int? _replyToId;
  String? _replyToName;

  final ScrollController _scrollController = ScrollController();

  /// 当前需要定位高亮的评论 id（命中后滚动到该条并高亮，随后自动清除）。
  int? _focusId;

  /// 是否已执行过一次定位（防止发评论后重载再次触发）。
  bool _didFocus = false;

  final ImagePicker _picker = ImagePicker();
  XFile? _image;
  bool _pickingImage = false;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final CommentLoader _loader;
  late final CommentPoster _poster;
  late final CommentLiker _liker;
  late final CommentPinner _pinner;
  late final CommentDeleter _deleter;

  bool get _loggedIn => widget.isLoggedIn ?? AuthSession.instance.isLoggedIn;
  bool get _owner => widget.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    _loader = widget.commentLoader ?? ApiClient.instance.getCardComments;
    _poster = widget.commentPoster ?? ApiClient.instance.postCardComment;
    _liker = widget.commentLiker ?? ApiClient.instance.toggleCommentLike;
    _pinner = widget.commentPinner ?? ApiClient.instance.toggleCommentPin;
    _deleter = widget.commentDeleter ?? ApiClient.instance.deleteComment;
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---- 数据 ----

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final page = await _loader(
        widget.cardId,
        page: 1,
        sort: _sort,
        onlyAuthor: _onlyAuthor,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _page = page.page;
        _total = page.total;
        _hasNext = page.hasNext;
        _loading = false;
      });
      _maybeFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '评论加载失败';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _loader(
        widget.cardId,
        page: _page + 1,
        sort: _sort,
        onlyAuthor: _onlyAuthor,
      );
      if (!mounted) return;
        setState(() {
          _items = <Comment>[..._items, ...page.items];
          _page = page.page;
          _total = page.total;
          _hasNext = page.hasNext;
        });
    } catch (_) {
      if (!mounted) return;
      _showSnack('加载更多失败，请重试');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ---- 定位评论（从用户主页点击进入）----

  /// 在已加载的评论里查找 [widget.focusCommentId]，滚动到该条并高亮。
  void _maybeFocus() {
    final target = widget.focusCommentId;
    if (target == null || _didFocus) return;
    final idx = _items.indexWhere((c) => c.id == target);
    if (idx < 0) return;
    _didFocus = true;
    setState(() => _focusId = target);
    // 列表渲染完成后滚动到该条。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _focusKey(target);
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          (idx * 120.0).clamp(
              0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
      // 高亮持续一段时间后自动淡出。
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _focusId = null);
      });
    });
  }

  // ---- 交互 ----

  Future<void> _post() async {
    if (!_loggedIn) {
      _showSnack('请先登录后再评论');
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty && _image == null) return;
    final replyId = _replyToId;
    final imageData = await _readImageData();
    if (imageData == null && _image != null) {
      _showSnack('图片读取失败，请重试');
      return;
    }
    setState(() => _posting = true);
    try {
      await _poster(widget.cardId, text, replyToId: replyId, imageData: imageData);
      if (!mounted) return;
      _controller.clear();
      _replyToId = null;
      _replyToName = null;
      _image = null;
      _showSnack('评论成功');
      await _reload();
    } catch (_) {
      if (!mounted) return;
      _showSnack('评论失败，请重试');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// 读取选中图片为 base64 data URL（与后端约定的 JSON 数据格式，服务端压缩为 WebP）。
  Future<String?> _readImageData() async {
    final file = _image;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'png';
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/png',
      };
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _image = picked);
    } catch (_) {
      if (!mounted) return;
      _showSnack('选择图片失败');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// 打开评论图片全屏查看（WebP base64 data URL）。
  void _openImage(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return;
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    Uint8List? bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) return;
    final Uint8List imageBytes = bytes;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(imageBytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startReply(Comment c) {
    final name = c.author != null
        ? (c.author!.nickname.isNotEmpty
            ? c.author!.nickname
            : c.author!.username)
        : '用户';
    setState(() {
      _replyToId = c.id;
      _replyToName = name;
    });
    FocusScope.of(context).requestFocus(_focusNode);
  }

  void _cancelReply() =>
      setState(() => _replyToId = _replyToName = null);

  Future<void> _like(Comment c) async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再点赞');
      return;
    }
    final prevLiked = c.liked;
    final prevCount = c.likeCount;
    _applyToTree(c.id, (x) => x.copyWith(
          liked: !prevLiked,
          likeCount: prevCount + (prevLiked ? -1 : 1),
        ));
    try {
      final res = await _liker(widget.cardId, c.id);
      _applyToTree(c.id, (x) => x.copyWith(liked: res.liked, likeCount: res.count));
    } catch (_) {
      _applyToTree(c.id, (x) => x.copyWith(liked: prevLiked, likeCount: prevCount));
      if (mounted) _showSnack('操作失败，请重试');
    }
  }

  Future<void> _pin(Comment c) async {
    if (!_loggedIn) return;
    final prev = c.isPinned;
    _applyToTree(c.id, (x) => x.copyWith(isPinned: !prev));
    try {
      final next = await _pinner(widget.cardId, c.id);
      _applyToTree(c.id, (x) => x.copyWith(isPinned: next));
    } catch (_) {
      _applyToTree(c.id, (x) => x.copyWith(isPinned: prev));
      if (mounted) _showSnack('操作失败，请重试');
    }
  }

  Future<void> _delete(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定要删除这条评论吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _deleter(widget.cardId, c.id);
      if (!mounted) return;
      setState(() {
        _items = _removeFromTree(_items, c.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
      _showSnack('已删除评论');
    } catch (_) {
      if (mounted) _showSnack('删除失败，请重试');
    }
  }

  // ---- 树操作 ----

  void _applyToTree(int id, Comment Function(Comment) updater) {
    setState(() => _items = _replaceInTree(_items, id, updater));
  }

  List<Comment> _replaceInTree(
    List<Comment> list,
    int id,
    Comment Function(Comment) updater,
  ) {
    return list.map((c) {
      if (c.id == id) return updater(c);
      if (c.replies.isNotEmpty) {
        return c.copyWith(replies: _replaceInTree(c.replies, id, updater));
      }
      return c;
    }).toList();
  }

  List<Comment> _removeFromTree(List<Comment> list, int id) {
    final out = <Comment>[];
    for (final c in list) {
      if (c.id == id) continue;
      out.add(c.copyWith(replies: _removeFromTree(c.replies, id)));
    }
    return out;
  }

  void _setSort(String s) {
    if (_sort == s) return;
    setState(() => _sort = s);
    _reload();
  }

  void _toggleOnlyAuthor(bool v) {
    if (_onlyAuthor == v) return;
    setState(() => _onlyAuthor = v);
    _reload();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 打开表情包选择器，把选中的 `[sticker:CODE]` 插入到评论输入框光标处。
  Future<void> _openStickerPicker() async {
    final token = await showStickerPicker(context);
    if (token == null || !mounted) return;
    final controller = _controller;
    final value = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    controller.text = value.replaceRange(start, end, token);
    controller.selection = TextSelection.collapsed(
      offset: start + token.length,
    );
    _focusNode.requestFocus();
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        Divider(height: 1, color: scheme.outlineVariant),
        // 评论列表占满剩余高度；输入框固定在底部，评论再多也不用翻到最底。
        Expanded(child: _buildList(context)),
        _buildComposer(),
      ],
    );
  }

  /// 头部：评论数 + 最新/最热 + 只看作者。
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '评论（$_total）',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text('最新'),
                selected: _sort == 'latest',
                onSelected: (_) => _setSort('latest'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('最热'),
                selected: _sort == 'hottest',
                onSelected: (_) => _setSort('hottest'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilterChip(
            label: const Text('只看作者'),
            selected: _onlyAuthor,
            onSelected: _toggleOnlyAuthor,
          ),
        ],
      ),
    );
  }

  /// 评论列表（可滚动）；输入框不随列表滚动，始终固定在底部。
  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _reload,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '还没有评论，来抢沙发~',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return AppRefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: <Widget>[
        ..._items.map((c) => _buildComment(c, false)),
        if (_hasNext)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _loadingMore
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Center(
                    child: TextButton(
                      onPressed: _loadMore,
                      child: const Text('加载更多评论'),
                    ),
                  ),
          ),
      ],
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_replyToName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Chip(
                label: Text('回复 @$_replyToName'),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: _cancelReply,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: _loggedIn ? '说点什么…' : '登录后参与评论',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    counterText: _loggedIn ? '${_controller.text.length}/500' : '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_loggedIn) ...[
                IconButton(
                  onPressed: _pickingImage ? null : _pickImage,
                  tooltip: '图片',
                  icon: const Icon(Icons.image_outlined),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: _openStickerPicker,
                  tooltip: '表情包',
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              AsyncActionButton(
                variant: AsyncButtonVariant.tonal,
                enabled: _loggedIn && !_posting,
                tooltip: '发送',
                loadingSize: 24,
                onPressed: _post,
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_image!.path),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 64,
                        height: 64,
                        child: ColoredBox(color: Colors.black12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => _image = null),
                    tooltip: '移除图片',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '已添加图片，发送后随评论展示',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          if (!_loggedIn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '登录后才可发表评论',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComment(Comment c, bool isReply) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = c.author;
    final name = author != null
        ? (author.nickname.isNotEmpty ? author.nickname : author.username)
        : '用户';
    final focused = c.id == _focusId;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      key: focused ? _focusKey(c.id) : null,
      decoration: BoxDecoration(
        color: focused ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: 14, left: isReply ? 36 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Avatar(avatar: author?.avatar ?? '', radius: isReply ? 16 : 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: UserBadge(
                        name: name,
                        isSponsor: author?.isSponsor == true,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    if (c.isAuthor) ...<Widget>[
                      const SizedBox(width: 6),
                      _tag('作者', scheme.primaryContainer,
                          scheme.onPrimaryContainer),
                    ],
                    if (c.isPinned) ...<Widget>[
                      const SizedBox(width: 6),
                      _tag('置顶', scheme.tertiaryContainer,
                          scheme.onTertiaryContainer),
                    ],
                    const Spacer(),
                    if (c.floor != null)
                      Text(
                        '#${c.floor}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.outline),
                      ),
                  ],
                ),
                if (c.replyTo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '回复 @${c.replyTo!.authorName}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.outline),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StickerText(c.content, style: theme.textTheme.bodyMedium),
                ),
                if (c.hasImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _CommentImage(
                      dataUrl: c.imageData,
                      onTap: () => _openImage(c.imageData),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: <Widget>[
                      _likeButton(comment: c, onTap: () => _like(c)),
                      // 楼中楼最多两层：第二层回复不再提供「回复」入口。
                      if (!isReply)
                        TextButton(
                          onPressed: () => _startReply(c),
                          child: const Text('回复'),
                        ),
                      const Spacer(),
                      if (c.isMine || _owner)
                        _commentMenu(
                          comment: c,
                          owner: _owner,
                          onPin: () => _pin(c),
                          onDelete: () => _delete(c),
                        ),
                    ],
                  ),
                ),
                if (c.replies.isNotEmpty)
                  ...c.replies.map((r) => _buildComment(r, true)),
                if (c.createdAt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTime(c.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.outline),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// 定位评论时给目标评论挂的 GlobalKey。
  GlobalKey _focusKey(int id) => GlobalKey(debugLabel: 'focus-$id');

  Widget _likeButton({
    required Comment comment,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(
              comment.liked ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: comment.liked ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text('${comment.likeCount}', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  Widget _commentMenu({
    required Comment comment,
    required bool owner,
    required VoidCallback onPin,
    required VoidCallback onDelete,
  }) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 18),
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        if (owner)
          PopupMenuItem<String>(
            value: 'pin',
            child: Text(comment.isPinned ? '取消置顶' : '置顶'),
          ),
        if (comment.isMine)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Text('删除'),
          ),
      ],
      onSelected: (v) {
        if (v == 'pin') onPin();
        if (v == 'delete') onDelete();
      },
    );
  }
}

/// 小标签（作者 / 置顶）。
Widget _tag(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );

String _formatTime(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  return '${t.year}-$m-$d';
}

/// 评论图片缩略图（WebP base64 data URL），点按进全屏查看。
class _CommentImage extends StatelessWidget {
  const _CommentImage({required this.dataUrl, this.onTap});

  final String? dataUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dataUrl = this.dataUrl;
    if (dataUrl == null || dataUrl.isEmpty) {
      return Text(
        '[图片]',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      );
    }
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    Uint8List? bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) {
      return Text(
        '[图片]',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          bytes,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            width: 180,
            height: 180,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}
