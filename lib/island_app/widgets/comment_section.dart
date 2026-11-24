import 'dart:convert';
import '../../widgets/memo_image.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dna/island_app/widgets/state_views.dart';

import 'package:image_picker/image_picker.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/models/comment.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/user_badge.dart';
import 'package:dna/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import 'package:dna/utils/action_table.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/widgets/paged_controller.dart';
import '../../theme/tokens.dart';

/// 评论列表加载（GET /cards/`id`/comments）。
typedef CommentLoader =
    Future<CommentPage> Function(
      String cardId, {
      int page,
      String sort,
      bool onlyAuthor,
    });

/// 发表评论（POST /cards/`id`/comments）。
typedef CommentPoster =
    Future<int> Function(
      String cardId,
      String content, {
      int? replyToId,
      String? imageData,
    });

/// 评论点赞/取消。
typedef CommentLiker =
    Future<({bool liked, int count})> Function(String cardId, int commentId);

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
  int _total = 0;
  String _sort = 'latest';
  bool _onlyAuthor = false;
  bool _posting = false;
  int? _replyToId;
  String? _replyToName;

  /// 评论列表的分页状态（加载中 / 加载更多 / 有没有下一页 / 页码 / 错误）
  /// 交给共享 [PagedController]；本页只提供「怎么取一页」。
  late final PagedController<Comment> _paged = PagedController<Comment>(
    fetch: (int page) async {
      try {
        final CommentPage data = await _loader(
          widget.cardId,
          page: page,
          sort: _sort,
          onlyAuthor: _onlyAuthor,
        );
        // 总数只供页头「评论（N）」使用，与分页状态无关：失败时保持旧值。
        _total = data.total;
        return PagedResult<Comment>(items: data.items, hasMore: data.hasNext);
      } catch (_) {
        // 旧行为：翻页失败给一句提示；首屏失败走错误态，不重复提示。
        if (page > 1) _showSnack('加载更多失败，请重试');
        rethrow;
      }
    },
    onChanged: () {
      if (mounted) setState(() {});
    },
    firstLoadError: '评论加载失败',
  );

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
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _paged.dispose();
    super.dispose();
  }

  // ---- 数据 ----

  /// 首屏 / 刷新 / 重试：分页交给 [PagedController]，这里只补上「定位到某条
  /// 评论」这件页面自己的滚动事（不属于分页状态机）。
  Future<void> _refresh() async {
    await _paged.refresh();
    if (!mounted) return;
    _maybeFocus();
  }

  // ---- 定位评论（从用户主页点击进入）----

  /// 在已加载的评论里查找 [widget.focusCommentId]，滚动到该条并高亮。
  void _maybeFocus() {
    final target = widget.focusCommentId;
    if (target == null || _didFocus) return;
    final idx = _paged.items.indexWhere((c) => c.id == target);
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
          duration: AppMotion.transform,
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          (idx * 120.0).clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: AppMotion.transform,
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
      await _poster(
        widget.cardId,
        text,
        replyToId: replyId,
        imageData: imageData,
      );
      if (!mounted) return;
      _controller.clear();
      _replyToId = null;
      _replyToName = null;
      _image = null;
      _showSnack('评论成功');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _showSnack('评论失败：${describeError(e)}');
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
    } catch (e) {
      if (!mounted) return;
      _showSnack('选择图片失败：${describeError(e)}');
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

  void _cancelReply() => setState(() => _replyToId = _replyToName = null);

  Future<void> _like(Comment c) async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再点赞');
      return;
    }
    final prevLiked = c.liked;
    final prevCount = c.likeCount;
    _applyToTree(
      c.id,
      (x) => x.copyWith(
        liked: !prevLiked,
        likeCount: prevCount + (prevLiked ? -1 : 1),
      ),
    );
    try {
      final res = await _liker(widget.cardId, c.id);
      _applyToTree(
        c.id,
        (x) => x.copyWith(liked: res.liked, likeCount: res.count),
      );
    } catch (e) {
      _applyToTree(
        c.id,
        (x) => x.copyWith(liked: prevLiked, likeCount: prevCount),
      );
      if (mounted) _showSnack('操作失败：${describeError(e)}');
    }
  }

  Future<void> _pin(Comment c) async {
    if (!_loggedIn) return;
    final prev = c.isPinned;
    _applyToTree(c.id, (x) => x.copyWith(isPinned: !prev));
    try {
      final next = await _pinner(widget.cardId, c.id);
      _applyToTree(c.id, (x) => x.copyWith(isPinned: next));
    } catch (e) {
      _applyToTree(c.id, (x) => x.copyWith(isPinned: prev));
      if (mounted) _showSnack('操作失败：${describeError(e)}');
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
        _paged.items
          ..clear()
          ..addAll(_removeFromTree(_paged.items, c.id));
        _total = _total > 0 ? _total - 1 : 0;
      });
      _showSnack('已删除评论');
    } catch (e) {
      if (mounted) _showSnack('删除失败：${describeError(e)}');
    }
  }

  // ---- 树操作 ----

  void _applyToTree(int id, Comment Function(Comment) updater) {
    final List<Comment> next = _replaceInTree(_paged.items, id, updater);
    // 控制器持有的列表不能整体换掉，原地替换内容。
    setState(() {
      _paged.items
        ..clear()
        ..addAll(next);
    });
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
    _refresh();
  }

  void _toggleOnlyAuthor(bool v) {
    if (_onlyAuthor == v) return;
    setState(() => _onlyAuthor = v);
    _refresh();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showSnack(context, msg, duration: const Duration(seconds: 2));
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
              Expanded(
                child: Text(
                  '评论（$_total）',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 排序：互斥 2 项、常显 → SegmentedButton（与探索/世界/茶馆/
              // 搜索同一个控件；原来是两个 ChoiceChip，样子和别处都不一样）。
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'latest', label: Text('最新')),
                  ButtonSegment<String>(value: 'hottest', label: Text('最热')),
                ],
                selected: <String>{_sort},
                onSelectionChanged: (Set<String> picked) =>
                    _setSort(picked.first),
                // 不压密度：保留 M3 默认的 40dp 高度。

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
    if (_paged.isLoading && _paged.items.isEmpty) {
      return const LoadingState();
    }
    if (_paged.error != null && _paged.items.isEmpty) {
      return ErrorState(message: _paged.error!, onRetry: _refresh);
    }
    if (_paged.items.isEmpty) {
      return const EmptyState(title: '还没有评论，来抢沙发~');
    }
    return AppRefreshIndicator(
      onRefresh: _refresh,
      // 触底加载：与茶馆 / 世界 / 通知同一套规则（评论也是内容流，卡片高，
      // 因此用 feed 阈值 kLoadMoreFeedThreshold=300）。
      //
      // 监听只包住 ListView 这一层 —— 输入框在 Column 的下一格，不会被卷进来
      // （也不会因为滚动列表而触发分页）。
      child: loadMoreListener(
        onReachEnd: _paged.loadMore,
        threshold: kLoadMoreFeedThreshold,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: <Widget>[
            ..._paged.items.map((c) => _buildComment(c, false)),
            // 尾部状态行（原来是「加载更多评论」按钮）：
            // * 正在加载 → spinner；
            // * 还有下一页但没在加载 → 同高占位，滚到底即可继续（无限滚动没有按钮）。
            // 没有更多时什么都不画，保持原来的行为。
            if (_paged.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.lg,
                ),
                child: Center(
                  child: _paged.isLoadingMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const SizedBox(height: 20),
                ),
              ),
          ],
        ),
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
                    counterText: _loggedIn
                        ? '${_controller.text.length}/500'
                        : '',
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
                    borderRadius: BorderRadius.circular(AppRadius.xs),
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          if (!_loggedIn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '登录后才可发表评论',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                ),
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
      duration: AppMotion.medium,
      key: focused ? _focusKey(c.id) : null,
      decoration: BoxDecoration(
        color: focused ? scheme.primaryContainer.withValues(alpha: AppAlpha.a35) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        _tag(
                          '作者',
                          scheme.primaryContainer,
                          scheme.onPrimaryContainer,
                        ),
                      ],
                      if (c.isPinned) ...<Widget>[
                        const SizedBox(width: 6),
                        _tag(
                          '置顶',
                          scheme.tertiaryContainer,
                          scheme.onTertiaryContainer,
                        ),
                      ],
                      const Spacer(),
                      if (c.floor != null)
                        Text(
                          '#${c.floor}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                    ],
                  ),
                  if (c.replyTo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '回复 @${c.replyTo!.authorName}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: StickerText(
                      c.content,
                      style: theme.textTheme.bodyMedium,
                    ),
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
                        formatRelativeTime(c.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
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

  Widget _likeButton({required Comment comment, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
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
    // 置顶只在卡作者处出现、删除只在自己发的评论上出现 —— 条件写成数据，
    // 画法交给共享 rowActionMenu（无项内图标，紧凑单行，按钮图标尺寸原样）。
    // 调用点已保证 owner / isMine 至少有一个成立，菜单里不会空。
    return rowActionMenu(
      icon: const Icon(Icons.more_horiz, size: 18),
      actions: <RowAction>[
        RowAction(
          id: 'pin',
          label: comment.isPinned ? '取消置顶' : '置顶',
          visible: owner,
          onSelected: onPin,
        ),
        RowAction(
          id: 'delete',
          label: '删除',
          visible: comment.isMine,
          onSelected: onDelete,
        ),
      ],
    );
  }
}

/// 小标签（作者 / 置顶）。
Widget _tag(String text, Color bg, Color fg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(AppRadius.xs),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: AppFontSize.tiny, color: fg),
  ),
);

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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    // 复用 provider：同一个 data URL 只解码一次，并按 180 逻辑像素限宽，
    // 不把原图整张解进缩略图（原来每次 build 都重新 base64Decode + 解码）。
    final int target =
        (180 * MediaQuery.devicePixelRatioOf(context)).clamp(180, 720).round();
    final ImageProvider? provider =
        MemoImage.dataUrl(dataUrl, cacheWidth: target);
    if (provider == null) {
      return Text(
        '[图片]',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image(
          image: provider,
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
