import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 茶馆帖子详情：展示主帖（含原帖链）+ 回复列表 + 发回复/点赞/收藏/编辑/删除。
class TeahousePostPage extends StatefulWidget {
  const TeahousePostPage({super.key, required this.postId});

  final int postId;

  @override
  State<TeahousePostPage> createState() => _TeahousePostPageState();
}

class _TeahousePostPageState extends State<TeahousePostPage> {
  TeaPost? _post;
  List<TeaPost> _chain = const <TeaPost>[];
  List<TeaPost> _replies = const <TeaPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _replyPage = 1;
  String? _error;

  final TextEditingController _replyController = TextEditingController();
  bool _replying = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 200) {
      _loadMoreReplies();
    }
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  String? get _myUsername => AuthSession.instance.user?['username']?.toString();

  bool get _isOwner => _post?.author?.username == _myUsername;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiClient.instance.getTeahousePostDetail(widget.postId);
      if (!mounted) return;
      final postRaw = d['post'];
      final chainRaw = d['chain'];
      final repliesRaw = d['replies'];
      setState(() {
        _post = postRaw is Map ? TeaPost.fromJson(_asMap(postRaw)) : null;
        _chain = chainRaw is List
            ? chainRaw
                .whereType<Map>()
                .map((e) => TeaPost.fromJson(_asMap(e)))
                .toList()
            : const <TeaPost>[];
        if (repliesRaw is Map) {
          final items = repliesRaw['items'];
          _replies = items is List
              ? items
                  .whereType<Map>()
                  .map((e) => TeaPost.fromJson(_asMap(e)))
                  .toList()
              : const <TeaPost>[];
          _noMore = repliesRaw['has_next'] != true;
          _replyPage = (repliesRaw['page'] as num?)?.toInt() ?? 1;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Map<String, dynamic> _asMap(dynamic m) =>
      (m as Map).map((k, v) => MapEntry(k.toString(), v));

  Future<void> _loadMoreReplies() async {
    if (_loadingMore || _noMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final d = await ApiClient.instance.getTeahousePostDetail(
        widget.postId,
        page: _replyPage + 1,
      );
      if (!mounted) return;
      final repliesRaw = d['replies'];
      if (repliesRaw is Map) {
        final items = repliesRaw['items'];
        final newItems = items is List
            ? items
                .whereType<Map>()
                .map((e) => TeaPost.fromJson(_asMap(e)))
                .toList()
            : const <TeaPost>[];
        setState(() {
          _replies = <TeaPost>[..._replies, ...newItems];
          _replyPage += 1;
          _noMore = repliesRaw['has_next'] != true;
          _loadingMore = false;
        });
      } else {
        setState(() => _loadingMore = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _submitReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;
    if (!_loggedIn) {
      _snack('请先登录后再回复');
      return;
    }
    setState(() => _replying = true);
    try {
      await ApiClient.instance.replyTeahousePost(widget.postId, content);
      _replyController.clear();
      if (!mounted) return;
      _snack('回复成功');
      await _load();
    } catch (_) {
      if (!mounted) return;
      _snack('回复失败，请重试');
    } finally {
      if (mounted) setState(() => _replying = false);
    }
  }

  /// 在回复输入框光标处插入表情包标记。
  Future<void> _openReplySticker() async {
    final token = await showStickerPicker(context);
    if (token == null || !mounted) return;
    final controller = _replyController;
    final value = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    controller.text = value.replaceRange(start, end, token);
    controller.selection = TextSelection.collapsed(offset: start + token.length);
  }

  Future<void> _toggleLike() async {
    if (!_loggedIn) {
      _snack('请先登录后再点赞');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseLike(widget.postId);
      if (!mounted || _post == null) return;
      setState(() {
        _post = _post!.copyWith(
          stats: _post!.stats.copyWith(liked: r.liked, likeCount: r.count),
        );
      });
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_loggedIn) {
      _snack('请先登录后再收藏');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseFavorite(widget.postId);
      if (!mounted || _post == null) return;
      setState(() {
        _post = _post!.copyWith(
          stats: _post!.stats.copyWith(
            favorited: r.favorited,
            replyCount: _post!.stats.replyCount,
          ),
        );
      });
      _snack(r.favorited ? '已收藏' : '已取消收藏');
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  /// 按 id 更新回复列表里某条回复的统计。
  void _updateReply(int id, TeaPostStats Function(TeaPostStats) change) {
    setState(() {
      _replies = _replies
          .map((r) => r.idInt == id ? r.copyWith(stats: change(r.stats)) : r)
          .toList();
    });
  }

  Future<void> _toggleReplyLike(int id) async {
    if (!_loggedIn) {
      _snack('请先登录后再点赞');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseLike(id);
      if (!mounted) return;
      _updateReply(id, (s) => s.copyWith(liked: r.liked, likeCount: r.count));
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  Future<void> _toggleReplyFavorite(int id) async {
    if (!_loggedIn) {
      _snack('请先登录后再收藏');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseFavorite(id);
      if (!mounted) return;
      _updateReply(id, (s) => s.copyWith(favorited: r.favorited, likeCount: s.likeCount));
      _snack(r.favorited ? '已收藏' : '已取消收藏');
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  /// 编辑帖子（作者）：修改正文与可选话题、更换/移除配图。
  Future<void> _editPost() async {
    final post = _post;
    if (post == null || !_loggedIn) {
      _snack('请先登录');
      return;
    }
    final contentController = TextEditingController(text: post.content);
    final topicController = TextEditingController(
      text: post.stats.topics.isNotEmpty ? post.stats.topics.first.name : '',
    );
    var removeImage = false;
    XFile? pickedImage;
    var pickingImage = false;
    final picker = ImagePicker();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pick() async {
            if (pickingImage) return;
            setSheetState(() => pickingImage = true);
            try {
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 1280,
                maxHeight: 1280,
                imageQuality: 82,
              );
              if (picked == null) return;
              setSheetState(() {
                pickedImage = picked;
                removeImage = false;
              });
            } catch (_) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('选择图片失败')),
                );
              }
            } finally {
              if (ctx.mounted) setSheetState(() => pickingImage = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('编辑帖子',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    maxLength: 280,
                    decoration: const InputDecoration(
                      hintText: '帖子内容…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextField(
                    controller: topicController,
                    decoration: const InputDecoration(
                      hintText: '话题（可选）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 配图区域：显示当前配图 + 可选更换/移除。
                  if (post.image != null || pickedImage != null) ...<Widget>[
                    _buildEditImagePreview(
                      context: context,
                      existingUrl:
                          post.image != null && pickedImage == null
                              ? post.image!.url
                              : null,
                      pickedImage: pickedImage,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickingImage ? null : pick,
                            icon: pickingImage
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.add_photo_alternate_outlined,
                                    size: 18),
                            label: Text(
                              pickedImage != null ? '重新选择图片' : '更换图片',
                            ),
                          ),
                        ),
                        if (post.image != null) ...[
                          const SizedBox(width: 8),
                          Checkbox(
                            value: removeImage,
                            onChanged: (v) => setSheetState(() {
                              removeImage = v ?? false;
                              if (removeImage) pickedImage = null;
                            }),
                          ),
                          InkWell(
                            onTap: () => setSheetState(() {
                              removeImage = true;
                              pickedImage = null;
                            }),
                            child: const Text('移除'),
                          ),
                        ],
                      ],
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: pickingImage ? null : pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 18),
                      label: const Text('添加配图'),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    final newContent = contentController.text.trim();
    final newTopic = topicController.text.trim();
    contentController.dispose();
    topicController.dispose();
    if (saved != true) return;

    if (newContent.isEmpty) {
      _snack('正文不能为空');
      return;
    }
    String? imageData;
    if (!removeImage && pickedImage != null) {
      imageData = await _readEditImageData(pickedImage);
      if (imageData == null) {
        _snack('图片读取失败，请重试');
        return;
      }
    }
    try {
      await ApiClient.instance.editTeahousePost(
        widget.postId,
        content: newContent,
        topic: newTopic.isEmpty
            ? (post.stats.topics.isNotEmpty ? '' : null)
            : newTopic,
        imageRemoved: removeImage,
        imageData: imageData,
      );
      if (!mounted) return;
      _snack('已保存');
      await _load();
    } catch (_) {
      if (!mounted) return;
      _snack('保存失败，请重试');
    }
  }

  /// 编辑配图预览：有选择新图时预览本地图，否则展示原帖配图（若存在）。
  Widget _buildEditImagePreview({
    required BuildContext context,
    required String? existingUrl,
    required XFile? pickedImage,
  }) {
    if (pickedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(pickedImage.path),
          fit: BoxFit.cover,
          height: 140,
          width: double.infinity,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    final url = existingUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        ServerConfig.resolveUrl(url),
        fit: BoxFit.cover,
        height: 140,
        width: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  /// 读取选中的编辑图片为 base64 data URL（后端会再压缩为 WebP）。
  Future<String?> _readEditImageData(XFile? file) async {
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'png';
      final mime = _editImageMimeOf(ext);
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  String _editImageMimeOf(String ext) {
    switch (ext) {
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

  Future<void> _deletePost() async {
    if (!_loggedIn) {
      _snack('请先登录');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定删除这条帖子吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.deleteTeahousePost(widget.postId);
      if (!mounted) return;
      _snack('已删除');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      _snack('删除失败，请重试');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = _post;
    return Scaffold(
      appBar: AppBar(
        title: const Text('帖子详情'),
        actions: <Widget>[
          if (post != null && _isOwner)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _editPost();
                if (v == 'delete') _deletePost();
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('编辑帖子'),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('删除帖子'),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : _error != null && post == null
              ? ErrorState(message: _error!, onRetry: _load)
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: AppRefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          children: <Widget>[
                          if (_chain.isNotEmpty) ...<Widget>[
                            const _SectionLabel('原帖链'),
                            ..._chain.map(
                                (c) => _ChainTile(
                                  post: c,
                                  onTap: () => _openPost(c.idInt),
                                )),
                          ],
                          if (post != null) ...<Widget>[
                            const _SectionLabel('主帖'),
                            TeahousePostTile(
                              post: post,
                              onTap: () {},
                              onCardTap: post.card != null
                                  ? () => _openCard(post.card!.id)
                                  : null,
                              onLike: _toggleLike,
                              onFavorite: _toggleFavorite,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: <Widget>[
                                  _ActionButton(
                                    icon: post.stats.liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    label: '${post.stats.likeCount}',
                                    active: post.stats.liked,
                                    activeColor: scheme.error,
                                    onTap: _toggleLike,
                                  ),
                                  const SizedBox(width: 12),
                                  _ActionButton(
                                    icon: post.stats.favorited
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    label: '收藏',
                                    active: post.stats.favorited,
                                    activeColor: scheme.tertiary,
                                    onTap: _toggleFavorite,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          _SectionLabel('回复 (${post?.stats.replyCount ?? 0})'),
                          if (_replies.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('还没有回复')),
                            )
                          else
                            ..._replies.map((r) => TeahousePostTile(
                                  post: r,
                                  onTap: () => _openPost(r.idInt),
                                  onCardTap: r.card != null
                                      ? () => _openCard(r.card!.id)
                                      : null,
                                  onLike: () => _toggleReplyLike(r.idInt),
                                  onFavorite: () =>
                                      _toggleReplyFavorite(r.idInt),
                                )),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else if (_noMore && _replies.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: Text('没有更多回复了',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                            ),
                        ],
                      ),
                      ),
                    ),
                    _ReplyBar(
                      controller: _replyController,
                      sending: _replying,
                      onSend: _submitReply,
                      onSticker: _openReplySticker,
                    ),
                  ],
                ),
    );
  }

  void _openCard(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: id)),
    );
  }

  /// 打开另一条帖子的详情（原帖链/回复再点进去，像推特那样层层深入）。
  void _openPost(int postId) {
    if (postId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TeahousePostPage(postId: postId)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 原帖链上的帖子：展示作者 + 内容，点击可进入该帖详情（层层深入）。
class _ChainTile extends StatelessWidget {
  const _ChainTile({required this.post, this.onTap});
  final TeaPost post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Avatar(avatar: post.author?.avatar ?? '', radius: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    post.author?.displayName ?? '未知用户',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  StickerText(post.content,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? (activeColor ?? scheme.primary) : scheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

/// 底部回复输入栏。
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onSticker,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onSticker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: <Widget>[
            if (onSticker != null)
              IconButton(
                onPressed: onSticker,
                tooltip: '表情包',
                icon: const Icon(Icons.emoji_emotions_outlined),
                visualDensity: VisualDensity.compact,
              ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 280,
                decoration: const InputDecoration(
                  hintText: '写下你的回复…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    tooltip: '回复',
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}
