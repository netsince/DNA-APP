import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/teahouse_compose_page.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/comment_section.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';
import 'package:dna/island_app/widgets/image_viewer.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/user_badge.dart';

/// 角色卡详情数据模型（对应后端 `GET /api/v1/cards/<id>` 的 data）。
class CardDetail {
  CardDetail({
    required this.id,
    required this.name,
    required this.gender,
    required this.persona,
    required this.intro,
    required this.opening,
    required this.originalLink,
    required this.viewCount,
    required this.copyCount,
    required this.likeCount,
    required this.favoriteCount,
    required this.commentCount,
    required this.liked,
    required this.favorited,
    required this.tags,
    required this.dialogue,
    required this.images,
    required this.coverFocus,
    required this.createdAt,
    required this.updatedAt,
    required this.authorName,
    required this.authorUsername,
    required this.status,
    required this.isHidden,
    this.authorNote,
    this.authorNoteInterval = 0,
  });

  factory CardDetail.fromJson(Map<String, dynamic> m) {
    final author = m['author'];
    String? authorName;
    String? authorUsername;
    if (author is Map) {
      authorName =
          ((author['nickname'] ?? '').toString().isNotEmpty)
              ? (author['nickname'] ?? '').toString()
              : (author['display_name'] ?? '').toString();
      authorUsername = (author['username'] ?? '').toString();
    }

    final tags = <String>[];
    final rawTags = m['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t != null) tags.add(t.toString());
      }
    }

    final dialogue = <DialogueTurn>[];
    final rawDialogue = m['dialogue'];
    if (rawDialogue is List) {
      for (final turn in rawDialogue) {
        if (turn is Map) {
          dialogue.add(DialogueTurn(
            user: (turn['user'] ?? '').toString(),
            assistant: (turn['assistant'] ?? '').toString(),
          ));
        }
      }
    }

    final images = <String, String>{};
    final rawImages = m['images'];
    if (rawImages is Map) {
      rawImages.forEach((slot, path) {
        if (path is String && path.isNotEmpty) images[slot.toString()] = path;
      });
    }

    return CardDetail(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      gender: (m['gender'] ?? '').toString(),
      persona: (m['persona'] ?? '').toString(),
      intro: (m['intro'] ?? '').toString(),
      opening: (m['opening'] ?? '').toString(),
      originalLink: (m['original_link'] ?? '').toString(),
      viewCount: (m['view_count'] is num) ? (m['view_count'] as num).toInt() : 0,
      copyCount: (m['copy_count'] is num) ? (m['copy_count'] as num).toInt() : 0,
      likeCount: (m['like_count'] is num) ? (m['like_count'] as num).toInt() : 0,
      favoriteCount:
          (m['favorite_count'] is num) ? (m['favorite_count'] as num).toInt() : 0,
      commentCount:
          (m['comment_count'] is num) ? (m['comment_count'] as num).toInt() : 0,
      liked: m['liked'] == true || m['liked'] == 1,
      favorited: m['favorited'] == true || m['favorited'] == 1,
      tags: tags,
      dialogue: dialogue,
      images: images,
      coverFocus: (m['cover_focus'] ?? '').toString(),
      createdAt: (m['created_at'] ?? '').toString(),
      updatedAt: (m['updated_at'] ?? '').toString(),
      authorName: authorName,
      authorUsername: authorUsername,
      status: (m['status'] ?? 'approved').toString(),
      isHidden: m['is_hidden'] == true || m['is_hidden'] == 1,
      authorNote: (m['authorNote'] ?? '').toString(),
      authorNoteInterval:
          (m['authorNoteInterval'] is num)
              ? (m['authorNoteInterval'] as num).toInt()
              : (int.tryParse('${m['authorNoteInterval']}') ?? 0),
    );
  }

  final String id;
  final String name;
  final String gender;
  final String persona;
  final String intro;
  final String opening;
  final String originalLink;
  final int viewCount;
  final int copyCount;
  final int likeCount;
  final int favoriteCount;

  /// 评论数（详情接口返回，用于评论区入口按钮上的数字）。
  final int commentCount;

  final bool liked;
  final bool favorited;
  final List<String> tags;
  final List<DialogueTurn> dialogue;
  final Map<String, String> images;

  /// 封面焦点 `"x,y"`（0-100，作者在编辑页设置）；空串表示未设置焦点。
  final String coverFocus;

  final String createdAt;

  /// 最后更新时间（ISO8601；后端 `updated_at` 返回，未设置时为空串）。
  final String updatedAt;

  /// 作者注释（Author's Note）：希望模型始终记住/强调的内容；未设置时为空串。
  final String? authorNote;

  /// 作者注释注入间隔（条数）；0 表示禁用。仅当 [authorNote] 非空时生效。
  final int authorNoteInterval;

  final String? authorName;
  final String? authorUsername;

  /// 审核状态：`approved`/`rejected`/其他（审核中）。
  final String status;

  /// 是否已被作者隐藏。
  final bool isHidden;

  /// 横版封面路径（若存在）。
  String? get bannerPath => images['landscape'];

  /// 方形头像路径（若存在）。
  String? get avatarPath => images['square'];

  /// 是否启用封面 cover 模式（设置了封面焦点才会裁切填满，对齐网页版）。
  bool get coverEnabled =>
      bannerPath != null && coverFocus.trim().isNotEmpty && coverFocus.contains(',');

  /// 拷贝并覆盖点赞/收藏/隐藏等可变字段（其余保持不变）。
  CardDetail copyWith({
    bool? liked,
    bool? favorited,
    int? likeCount,
    int? favoriteCount,
    int? commentCount,
    bool? isHidden,
  }) {
    return CardDetail(
      id: id,
      name: name,
      gender: gender,
      persona: persona,
      intro: intro,
      opening: opening,
      originalLink: originalLink,
      viewCount: viewCount,
      copyCount: copyCount,
      likeCount: likeCount ?? this.likeCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      commentCount: commentCount ?? this.commentCount,
      liked: liked ?? this.liked,
      favorited: favorited ?? this.favorited,
      tags: tags,
      dialogue: dialogue,
      images: images,
      coverFocus: coverFocus,
      createdAt: createdAt,
      updatedAt: updatedAt,
      authorName: authorName,
      authorUsername: authorUsername,
      status: status,
      isHidden: isHidden ?? this.isHidden,
      authorNote: authorNote,
      authorNoteInterval: authorNoteInterval,
    );
  }
}

/// 对话示例的「一问一答」。
class DialogueTurn {
  DialogueTurn({required this.user, required this.assistant});
  final String user;
  final String assistant;
}

/// 详情数据加载函数（默认走后端 API，测试可注入 mock）。
typedef CardDetailLoader = Future<Map<String, dynamic>> Function(String cardId);

/// 点赞/收藏开关函数（返回 `(是否激活, 总数)`）。
typedef CardRelationToggler = Future<(bool, int)> Function(String cardId);

/// 作者资料加载函数（返回 `/api/v1/users/<username>` 的 data，测试可注入 mock）。
typedef AuthorLoader = Future<Map<String, dynamic>> Function(String username);

/// 关注/取关回调（返回是否「已关注」）。
typedef FollowToggler = Future<bool> Function(String username);

/// 举报原因加载函数（返回 `(key, label)` 列表，测试可注入 mock）。
typedef ReportReasonsLoader =
    Future<List<({String key, String label})>> Function();

/// 举报提交函数（type/id/reason/可选 detail）。
typedef ReportSubmitter = Future<void> Function(
  String type,
  String id,
  String reason,
  String? detail,
);

/// 复制/导出角色卡：返回可写入剪贴板的角色卡 JSON 包字符串（需登录）。
typedef CardExporter = Future<String> Function(String cardId);

/// 剪贴板写入函数（便于测试注入）。默认使用 [Clipboard.setData]。
typedef ClipboardWriter = Future<void> Function(String text);

/// 切换角色卡隐藏状态；返回切换后的 is_hidden。仅作者可用。
typedef CardHider = Future<bool> Function(String cardId);

/// 内置角色卡详情页：点击首页角色卡后打开的内置页面（而非外链网页）。
///
/// 布局参考网页版 `user/card_detail.html`：
/// - 顶部封面 hero：默认居中 contain（不铺满、不裁切），设置封面焦点后才 cover 填满，
///   并带左右/底部羽化淡出，与页面背景融合；
/// - 内容居中并限制最大宽度（宽屏/横屏下不铺满左右两边），宽屏采用「左资料栏 + 右内容」
///   双栏，且常驻侧边栏（由外壳承载）仍然保留；
/// - 简介 / 人格设定 / 开场白 / 对话示例。评论功能暂未接入。
class CardDetailPage extends StatefulWidget {
  const CardDetailPage({
    super.key,
    required this.cardId,
    this.focusCommentId,
    this.onBack,
    this.loader,
    this.likeToggler,
    this.favoriteToggler,
    this.authorLoader,
    this.followToggler,
    this.reasonsLoader,
    this.reportSubmitter,
    this.cardExporter,
    this.clipboardWriter,
    this.isLoggedIn,
    this.isOwner,
    this.cardHider,
  });

  final String cardId;

  /// 需要定位并高亮的评论 id（从用户主页点击评论进入时传入）。
  final int? focusCommentId;

  /// 返回回调；为 null 时由导航栈自动提供返回按钮（独立 push 场景）。
  final VoidCallback? onBack;

  /// 数据加载回调；为 null 时使用 [ApiClient.instance.getCardDetail]。
  final CardDetailLoader? loader;

  /// 点赞开关回调；为 null 时使用 [ApiClient.instance.toggleCardLike]。
  final CardRelationToggler? likeToggler;

  /// 收藏开关回调；为 null 时使用 [ApiClient.instance.toggleCardFavorite]。
  final CardRelationToggler? favoriteToggler;

  /// 作者资料加载回调；为 null 时使用 [ApiClient.instance.getUserProfile]。
  final AuthorLoader? authorLoader;

  /// 关注开关回调；为 null 时使用 [ApiClient.instance.toggleFollow]。
  final FollowToggler? followToggler;

  /// 举报原因加载回调；为 null 时使用 [ApiClient.instance.getReportReasons]。
  final ReportReasonsLoader? reasonsLoader;

  /// 举报提交回调；为 null 时使用 [ApiClient.instance.submitReport]。
  final ReportSubmitter? reportSubmitter;

  /// 复制/导出角色卡回调；为 null 时使用 [ApiClient.instance.exportCard]。
  final CardExporter? cardExporter;

  /// 剪贴板写入回调；为 null 时使用 [Clipboard.setData]。
  final ClipboardWriter? clipboardWriter;

  /// 切换隐藏状态回调；为 null 时使用 [ApiClient.instance.toggleCardHidden]。
  final CardHider? cardHider;

  /// 是否已登录；为 null 时读取 [AuthSession.instance.isLoggedIn]。
  final bool? isLoggedIn;

  /// 当前用户是否为该卡作者；为 null 时按 [AuthSession] 当前用户名与作者比对。
  final bool? isOwner;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  CardDetail? _detail;
  bool _loading = true;
  String? _error;

  /// 复制角色卡进行中（用于按钮 loading 态）。
  bool _copying = false;

  /// 复制网页链接进行中（用于按钮 loading 态）。
  bool _copyingLink = false;

  /// 切换隐藏状态进行中（菜单项禁用态）。
  bool _hiding = false;

  /// 关注作者进行中。
  bool _followBusy = false;

  // 作者板块（单独小板块）：跟随详情加载后异步拉取作者统计。
  bool _authorReady = false;
  String _authorAvatar = '';
  String _authorNickname = '';
  bool _authorVerified = false;
  /// 作者是否为赞助者（昵称旁红星）。
  bool _authorIsSponsor = false;
  int _followerCount = 0;
  int _cardCount = 0;
  bool _following = false;

  bool get _loggedIn => widget.isLoggedIn ?? AuthSession.instance.isLoggedIn;

  /// 是否为作者本人（控制审核状态徽章、隐藏徽章等作者可见信息）。
  bool get _owner => widget.isOwner ?? _isSelf;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader ?? ApiClient.instance.getCardDetail;
      final data = await loader(widget.cardId);
      if (!mounted) return;
      setState(() {
        _detail = CardDetail.fromJson(data);
        _loading = false;
      });
      await _loadAuthor();
      // 从用户主页点击某条评论进入时，自动打开评论区并定位到该评论。
      if (widget.focusCommentId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openComments();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 执行一次点赞/收藏开关，并更新本地详情。
  ///
  /// 防重与加载态由 [AsyncActionButton] 承担，这里只做业务与异常提示。
  Future<void> _toggle(
    CardRelationToggler toggler,
    void Function(CardDetail d, bool next, int count) apply,
  ) async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再操作');
      return;
    }
    final d = _detail;
    if (d == null) return;
    try {
      final (next, count) = await toggler(widget.cardId);
      if (!mounted) return;
      setState(() => apply(d, next, count));
    } catch (_) {
      _showSnack('操作失败，请重试');
    }
  }

  /// 复制/导出角色卡到剪贴板（需登录；未登录提示，异常降级）。
  Future<void> _copyCard() async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再复制');
      return;
    }
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final exporter = widget.cardExporter ?? ApiClient.instance.exportCard;
      final pkg = await exporter(widget.cardId);
      final writer = widget.clipboardWriter ??
          (text) => Clipboard.setData(ClipboardData(text: text));
      await writer(pkg);
      if (!mounted) return;
      _showSnack('已复制角色卡内容');
    } catch (_) {
      if (!mounted) return;
      _showSnack('复制失败，请重试');
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  /// 复制角色卡的网页版链接（`<服务器>/card/<card_id>`，无需登录）。
  Future<void> _copyCardLink() async {
    if (_copyingLink) return;
    setState(() => _copyingLink = true);
    final url = ServerConfig.resolveUrl('/card/${widget.cardId}');
    try {
      if (url.isEmpty) {
        _showSnack('尚未配置服务器地址');
        return;
      }
      final writer = widget.clipboardWriter ??
          (text) => Clipboard.setData(ClipboardData(text: text));
      await writer(url);
      if (!mounted) return;
      _showSnack('已复制网页链接');
    } catch (_) {
      if (!mounted) return;
      _showSnack('复制失败，请重试');
    } finally {
      if (mounted) setState(() => _copyingLink = false);
    }
  }

  /// 引用到茶馆：携带当前角色卡跳转发帖页。
  void _quoteToTeahouse() {
    final d = _detail;
    if (d == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahouseComposePage(
          presetCardId: d.id,
          presetCardName: d.name,
        ),
      ),
    );
  }

  /// 切换角色卡隐藏状态（仅作者；菜单项触发）。成功后更新本地 [isHidden]。
  Future<void> _toggleHidden() async {
    if (!_loggedIn) {
      _showSnack('请先登录后再操作');
      return;
    }
    if (_hiding) return;
    setState(() => _hiding = true);
    try {
      final hider = widget.cardHider ?? ApiClient.instance.toggleCardHidden;
      final nextHidden = await hider(widget.cardId);
      if (!mounted) return;
      _detail = _detail!.copyWith(isHidden: nextHidden);
      _showSnack(nextHidden ? '已隐藏角色卡' : '已取消隐藏');
    } catch (_) {
      if (!mounted) return;
      _showSnack('操作失败，请重试');
    } finally {
      if (mounted) setState(() => _hiding = false);
    }
  }

  Future<void> _toggleLike() => _toggle(
        widget.likeToggler ?? ApiClient.instance.toggleCardLike,
        (d, next, count) => _detail = d.copyWith(liked: next, likeCount: count),
      );

  Future<void> _toggleFavorite() => _toggle(
        widget.favoriteToggler ?? ApiClient.instance.toggleCardFavorite,
        (d, next, count) =>
            _detail = d.copyWith(favorited: next, favoriteCount: count),
      );

  /// 打开评论区：从底部弹出二级弹层（对齐网页版评论抽屉）。
  ///
  /// 评论区以独立弹层呈现，评论列表可滚动、输入框固定在底部，
  /// 评论再多也能随时发表而不必翻到页面最底。
  void _openComments() {
    final d = _detail;
    if (d == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: CommentSection(
          cardId: widget.cardId,
          isLoggedIn: widget.isLoggedIn,
          isOwner: _owner,
          focusCommentId: widget.focusCommentId,
        ),
      ),
    );
  }

  /// 拉取作者主页数据（头像/昵称/卡数/粉丝数/是否关注）。
  Future<void> _loadAuthor() async {
    final u = _detail?.authorUsername;
    if (u == null || u.isEmpty) return;
    final loader = widget.authorLoader ?? ApiClient.instance.getUserProfile;
    try {
      final data = await loader(u);
      final user = data['user'];
      final avatar = user is Map ? (user['avatar'] ?? '').toString() : '';
      final nickname = user is Map
          ? ((user['nickname'] ?? '').toString().isNotEmpty
              ? (user['nickname'] ?? '').toString()
              : (user['display_name'] ?? '').toString())
          : '';
      final follower = data['follower_count'];
      int cardCount = 0;
      final cards = data['cards'];
      if (cards is Map && (cards['total'] is num)) {
        cardCount = (cards['total'] as num).toInt();
      }
      if (!mounted) return;
      setState(() {
        _authorAvatar = avatar;
        _authorNickname = nickname.isEmpty ? _detail!.authorName ?? '' : nickname;
        _authorVerified = user is Map && user['verified'] == true;
        _authorIsSponsor = user is Map && user['is_sponsor'] == true;
        _followerCount = (follower is num) ? follower.toInt() : 0;
        _cardCount = cardCount;
        _following = data['is_following'] == true;
        _authorReady = true;
      });
    } catch (_) {
      // 作者统计拉取失败不阻塞页面，板块只展示基础信息。
    }
  }

  /// 关注/取关作者。
  Future<void> _toggleFollow() async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再关注');
      return;
    }
    if (_followBusy) return;
    final u = _detail?.authorUsername;
    if (u == null || u.isEmpty || _isSelf) return;
    setState(() => _followBusy = true);
    final fn = widget.followToggler ?? ApiClient.instance.toggleFollow;
    try {
      final following = await fn(u);
      if (!mounted) return;
      setState(() {
        _following = following;
        final v = _followerCount + (following ? 1 : -1);
        _followerCount = v < 0 ? 0 : v;
      });
    } catch (_) {
      _showSnack('操作失败，请重试');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// 作者是否就是当前登录用户（是则隐藏关注按钮）。
  bool get _isSelf {
    final author = _detail?.authorUsername;
    if (author == null || author.isEmpty) return false;
    final me = AuthSession.instance.user;
    return me != null && (me['username'] ?? '').toString() == author;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openLink(String url) async {
    await confirmOpenBrowser(context, url);
  }

  /// 点击头图/相册：全屏高品质查看原图（支持双击放大、手势拖拽关闭、多图滑动切换）。
  void _openImageViewer([String? targetUrl]) {
    final images = _detail?.images;
    if (images == null || images.isEmpty) {
      final banner = _detail?.bannerPath;
      if (banner != null) {
        ImageViewerPage.open(context, urls: <String>[ServerConfig.resolveUrl(banner)]);
      }
      return;
    }
    final urls = images.values.map((p) => ServerConfig.resolveUrl(p)).toList();
    final resolvedTarget = targetUrl != null ? ServerConfig.resolveUrl(targetUrl) : null;
    final initialIndex = resolvedTarget != null ? urls.indexOf(resolvedTarget) : 0;
    ImageViewerPage.open(
      context,
      urls: urls,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
  }

  /// 举报入口：需登录，弹底部表单选择原因并提交。
  Future<void> _openReport() async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再举报');
      return;
    }
    final detailId = _detail?.id;
    if (detailId == null || detailId.isEmpty) return;

    // 拉取举报原因（失败则用内置兜底）。
    List<({String key, String label})> reasons;
    try {
      reasons =
          await (widget.reasonsLoader ?? ApiClient.instance.getReportReasons)();
    } catch (_) {
      reasons = const [
        (key: 'spam', label: '垃圾广告 / 刷屏'),
        (key: 'porn', label: '色情低俗'),
        (key: 'violence', label: '暴力血腥'),
        (key: 'politics', label: '违规政治内容'),
        (key: 'abuse', label: '人身攻击 / 辱骂'),
        (key: 'copyright', label: '侵犯版权'),
        (key: 'other', label: '其他'),
      ];
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<({String key, String detail})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportSheet(
        reasons: reasons,
        onSubmitted: (key, detail) =>
            Navigator.of(context).pop((key: key, detail: detail)),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      final submit = widget.reportSubmitter ?? ApiClient.instance.submitReport;
      await submit('card', detailId, picked.key, picked.detail);
      if (!mounted) return;
      _showSnack('举报已提交，管理员会尽快处理');
    } catch (_) {
      _showSnack('举报提交失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 顶部返回：独立 push（无 onBack）时走系统自动返回；外壳承载时用显式返回按钮，
    // 并加一层圆形浅底，确保在任意封面上都清晰可见。
    final Widget? leading = widget.onBack != null
        ? Padding(
            padding: const EdgeInsets.only(left: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: widget.onBack,
              ),
            ),
          )
        : null;

    if (_loading) return _SkeletonBody(leading: leading);
    if (_error != null) {
      return _ErrorBody(leading: leading, error: _error!, onRetry: _load);
    }

    final d = _detail!;
    final wide = MediaQuery.sizeOf(context).width >= 860;
    // 内容最大宽度：宽屏双栏 / 窄屏单列，均居中限宽，避免铺满左右两边。
    final maxWidth = wide ? 1000.0 : 760.0;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          leading: leading,
          title: Text(d.name),
          actions: <Widget>[
            // 举报入口（更多菜单）。
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '更多',
              onSelected: (v) {
                if (v == 'toggle_hidden') _toggleHidden();
                if (v == 'copy_link') _copyCardLink();
                if (v == 'teahouse') _quoteToTeahouse();
                if (v == 'report') _openReport();
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                if (_owner)
                  PopupMenuItem<String>(
                    value: 'toggle_hidden',
                    enabled: !_hiding,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _detail!.isHidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(_detail!.isHidden ? '取消隐藏' : '隐藏'),
                      ],
                    ),
                  ),
                PopupMenuItem<String>(
                  value: 'copy_link',
                  enabled: !_copyingLink,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.link, size: 20),
                      const SizedBox(width: 12),
                      const Text('复制链接'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'teahouse',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.local_cafe_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('引用到茶馆'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.flag_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('举报'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (d.bannerPath != null)
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: _HeroBanner(
                    detail: d,
                    onTap: _openImageViewer,
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: wide ? _buildWide(d) : _buildNarrow(d),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// 窄屏（手机/竖屏）：资料卡 + 操作 + 作者板块 + 内容单列。
  Widget _buildNarrow(CardDetail d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProfileCard(detail: d, centered: false),
        _ActionsBar(detail: d, page: this),
        _authorSection(),
        ..._contentSectionChildren(d, includeTags: true),
      ],
    );
  }

  /// 宽屏（桌面/平板横屏）：左资料栏 + 右内容，对齐网页版桌面端。
  ///
  /// 作者板块置于左侧资料栏中（头像/昵称/卡数/粉丝数/关注）。
  Widget _buildWide(CardDetail d) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 左侧资料栏（桌面端居中堆叠，更整洁）。
        SizedBox(
          width: 288,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ProfileCard(detail: d, centered: true),
              _ActionsBar(detail: d, page: this),
              if (d.tags.isNotEmpty || _owner)
                _TagsSection(
                  tags: d.tags,
                  statusBadge: _owner ? _StatusBadge(detail: d) : null,
                ),
              _authorSection(),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ..._contentSectionChildren(d, includeTags: false),
            ],
          ),
        ),
      ],
    );
  }

  /// 作者板块：作者存在时显示（无作者或作者信息为空则不占位）。
  Widget _authorSection() {
    final d = _detail;
    final u = d?.authorUsername;
    if (d == null || u == null || u.isEmpty) return const SizedBox.shrink();
    return _AuthorSection(
      username: u,
      nickname: _authorNickname,
      avatar: _authorAvatar,
      verified: _authorVerified,
      isSponsor: _authorIsSponsor,
      cardCount: _authorReady ? _cardCount : null,
      followerCount: _authorReady ? _followerCount : null,
      isFollowing: _following,
      isSelf: _isSelf,
      onFollow: _toggleFollow,
      followBusy: _followBusy,
      onTapAuthor: _openAuthorProfile,
    );
  }

  /// 点击作者板块：进入该作者的内置主页详情页。
  void _openAuthorProfile() {
    final u = _detail?.authorUsername;
    if (u == null || u.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(username: u),
      ),
    );
  }

  /// 内容区块（简介/人格设定/开场白/对话示例/原始链接），窄屏与宽屏共用。
  ///
  /// [includeTags] 为 true 时包含标签区（窄屏），false 时标签由资料栏展示（宽屏）。
  List<Widget> _contentSectionChildren(CardDetail d, {required bool includeTags}) {
    return <Widget>[
      if (includeTags && (d.tags.isNotEmpty || _owner))
        _TagsSection(
          tags: d.tags,
          statusBadge: _owner ? _StatusBadge(detail: d) : null,
        ),
      if (d.intro.isNotEmpty)
        _ContentSection(
          icon: Icons.notes_outlined,
          title: '简介',
          body: d.intro,
        ),
      if (d.persona.isNotEmpty)
        _ContentSection(
          icon: Icons.badge_outlined,
          title: '人格设定',
          body: d.persona,
        ),
      if (d.opening.isNotEmpty)
        _ContentSection(
          icon: Icons.chat_bubble_outline,
          title: '开场白',
          // 开场白不做强斜体、不加装饰，保持 MDUI 简洁排版。
          body: d.opening,
        ),
      if (d.dialogue.isNotEmpty)
        _DialogueSection(name: d.name, dialogue: d.dialogue),
      if (d.authorNote != null && d.authorNote!.isNotEmpty)
        _AuthorNoteSection(
          note: d.authorNote!,
          interval: d.authorNoteInterval,
        ),
      if (d.originalLink.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _openLink(d.originalLink),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('原始链接'),
          ),
        ),
    ];
  }
}

/// 顶部封面 hero：固定横向 16:9 裁切显示横版封面图（`landscape`），保持简洁，
/// 不叠加任何渐变/羽化（对齐网页版横幅的干净观感）。点击可全屏查看原图。
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.detail, this.onTap});

  final CardDetail detail;

  /// 点击头图回调（打开全屏原图）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 网页版对齐：设了封面焦点才按焦点 cover 裁切填满；未设焦点则完整展示原图。
    final useFocus = detail.coverEnabled;
    final focus = useFocus ? _parseFocus(detail.coverFocus) : null;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: FadeInNetworkImage(
            url: ServerConfig.resolveUrl(detail.bannerPath!),
            fit: useFocus ? BoxFit.cover : BoxFit.contain,
            alignment: focus ?? Alignment.center,
            placeholder: ColoredBox(color: scheme.surfaceContainerHighest),
          ),
        ),
      ),
    );
    if (onTap == null) return image;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: <Widget>[
          image,
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.zoom_in, size: 14, color: scheme.onSurface),
                  const SizedBox(width: 4),
                  Text(
                    '查看原图',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 解析 "x,y" 百分比为 [Alignment]（0,0 左上；100,100 右下），解析失败返回 null。
  Alignment? _parseFocus(String s) {
    final parts = s.split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0].trim());
    final y = double.tryParse(parts[1].trim());
    if (x == null || y == null) return null;
    final ax = ((x / 50) - 1).clamp(-1.0, 1.0).toDouble();
    final ay = ((y / 50) - 1).clamp(-1.0, 1.0).toDouble();
    return Alignment(ax, ay);
  }
}

/// 资料卡：头像 + 名称/性别/作者/统计，带描边圆角卡片样式（对齐网页版 `.dna-card-profile`）。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.detail, required this.centered});

  final CardDetail detail;

  /// 宽屏资料栏中居中堆叠展示。
  final bool centered;

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  String _shortDate(String iso) {
    if (iso.length >= 10) return iso.substring(0, 10);
    return iso;
  }

  Widget _avatar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarPath = detail.avatarPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 84,
        height: 84,
        child: avatarPath != null
            ? FadeInNetworkImage(
                url: ServerConfig.resolveUrl(avatarPath),
                fit: BoxFit.cover,
                cacheWidth: 160,
                placeholder: ColoredBox(color: scheme.surfaceContainerHighest),
              )
            : ColoredBox(
                color: scheme.primaryContainer,
                child: Center(
                  child: Text(
                    detail.name.isNotEmpty ? detail.name[0] : '?',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final chips = <Widget>[
      if (detail.gender.isNotEmpty)
        _Chip(
          label: detail.gender,
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        ),
      if (detail.authorName != null && detail.authorName!.isNotEmpty)
        _Chip(
          label: detail.authorName!,
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
          icon: Icons.person_outline,
        ),
      if (detail.createdAt.isNotEmpty)
        _Chip(
          label: _shortDate(detail.createdAt),
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
          icon: Icons.calendar_today_outlined,
        ),
      if (detail.updatedAt.isNotEmpty &&
          _shortDate(detail.updatedAt) != _shortDate(detail.createdAt))
        _Chip(
          label: '更新 ${_shortDate(detail.updatedAt)}',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
          icon: Icons.update_outlined,
        ),
    ];

    final metaStyle =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    // 统计：浏览 / 复制，居中或居左随布局变化。
    final stats = Row(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.visibility_outlined,
            size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(_fmtCount(detail.viewCount), style: metaStyle),
        const SizedBox(width: 20),
        Icon(Icons.content_copy, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(_fmtCount(detail.copyCount), style: metaStyle),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: centered
          ? Column(
              children: <Widget>[
                _avatar(context),
                const SizedBox(height: 12),
                Text(
                  detail.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (chips.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: chips,
                  ),
                ],
                const SizedBox(height: 12),
                stats,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    _avatar(context),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            detail.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: chips,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                stats,
              ],
            ),
    );
  }
}

/// 作者板块：单独小板块，展示作者头像/昵称/用户名/角色卡数/粉丝数/关注按钮。
///
/// 宽屏布局下置于右侧内容区，窄屏下为单列中的独立卡片。
class _AuthorSection extends StatelessWidget {
  const _AuthorSection({
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.verified,
    required this.isSponsor,
    required this.cardCount,
    required this.followerCount,
    required this.isFollowing,
    required this.isSelf,
    required this.onFollow,
    this.followBusy = false,
    this.onTapAuthor,
  });

  final String username;
  final String nickname;
  final String avatar;

  /// 作者是否已认证（昵称旁显示小对勾）。
  final bool verified;

  /// 作者是否为赞助者（昵称旁显示红星）。
  final bool isSponsor;

  final int? cardCount;
  final int? followerCount;
  final bool isFollowing;
  final bool isSelf;

  /// 关注操作，点击后触发网络请求。
  final Future<void> Function() onFollow;

  /// 关注请求进行中（由外层 busy 控制，加载期间按钮显示转圈）。
  final bool followBusy;

  /// 点击整个作者板块跳转到作者主页。
  final VoidCallback? onTapAuthor;

  String _fmt(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = nickname.isNotEmpty ? nickname : username;

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _AuthorAvatar(avatar: avatar, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        UserBadge(
                          name: name,
                          isSponsor: isSponsor,
                          verified: verified,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!isSelf)
                AsyncActionButton(
                  variant: AsyncButtonVariant.tonal,
                  enabled: !followBusy,
                  onPressed: onFollow,
                  icon: Icon(
                    isFollowing ? Icons.check : Icons.add,
                    size: 16,
                    color: isFollowing ? scheme.onSurfaceVariant : null,
                  ),
                  style: isFollowing
                      ? FilledButton.styleFrom(
                          backgroundColor: scheme.surfaceContainerHigh,
                          foregroundColor: scheme.onSurfaceVariant,
                        )
                      : null,
                  child: Text(
                    isFollowing ? '已关注' : '关注',
                    style: TextStyle(
                      color: isFollowing ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _AuthorStat(
                icon: Icons.collections_bookmark_outlined,
                label: '角色卡',
                value: cardCount == null ? '…' : _fmt(cardCount!),
              ),
              const SizedBox(width: 24),
              _AuthorStat(
                icon: Icons.people_outline,
                label: '粉丝',
                value: followerCount == null ? '…' : _fmt(followerCount!),
              ),
            ],
          ),
        ],
      ),
    );

    // 整个作者板块可点击进入作者主页（由外壳/上层传入回调）。
    if (onTapAuthor != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTapAuthor,
            borderRadius: BorderRadius.circular(16),
            child: card,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: card,
    );
  }
}

/// 作者头像（支持 `data:` 或服务器相对路径）。
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.avatar, this.radius = 24});

  final String avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    final a = avatar;
    if (a.isEmpty) {
      child = Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant);
    } else if (a.startsWith('data:')) {
      final comma = a.indexOf(',');
      final bytes = base64Decode(comma >= 0 ? a.substring(comma + 1) : a);
      child = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
      );
    } else {
      child = Image.network(
        ServerConfig.resolveUrl(a),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: child,
        ),
      ),
    );
  }
}

/// 作者统计小项（图标 + 数值 + 标签）。
class _AuthorStat extends StatelessWidget {
  const _AuthorStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 5),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 操作栏：点赞 / 收藏（胶囊按钮）。
class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.detail, required this.page});

  final CardDetail detail;
  final _CardDetailPageState page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          // 评论（N）：打开评论区二级弹层（对齐网页版评论抽屉入口）。
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: page._openComments,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('${detail.commentCount}'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AsyncActionButton(
              variant: AsyncButtonVariant.tonal,
              onPressed: page._toggleLike,
              icon: Icon(
                detail.liked ? Icons.favorite : Icons.favorite_outline,
                size: 18,
              ),
              style: FilledButton.styleFrom(
                foregroundColor: detail.liked ? scheme.error : null,
                backgroundColor: detail.liked ? scheme.errorContainer : null,
              ),
              child: Text('${detail.likeCount}'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AsyncActionButton(
              variant: AsyncButtonVariant.tonal,
              onPressed: page._toggleFavorite,
              icon: Icon(
                detail.favorited ? Icons.bookmark : Icons.bookmark_outline,
                size: 18,
              ),
              style: FilledButton.styleFrom(
                foregroundColor: detail.favorited ? scheme.primary : null,
                backgroundColor:
                    detail.favorited ? scheme.primaryContainer : null,
              ),
              child: Text('${detail.favoriteCount}'),
            ),
          ),
          const SizedBox(width: 12),
          // 复制角色卡：将角色卡 JSON 包写入剪贴板（对齐网页版「复制卡片」）。
          AsyncActionButton(
            variant: AsyncButtonVariant.tonal,
            tooltip: '复制卡片',
            onPressed: page._copyCard,
            icon: const Icon(Icons.content_copy, size: 18),
            loadingSize: 18,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHigh,
              foregroundColor: scheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size.square(40),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// 标签区：横向排布的标签胶囊；作者可见时顶部叠加审核状态徽章。
class _TagsSection extends StatelessWidget {
  const _TagsSection({required this.tags, this.statusBadge});

  final List<String> tags;
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (statusBadge != null) ...<Widget>[
            statusBadge!,
            const SizedBox(height: 8),
          ],
          if (tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags
                  .map((t) => _Chip(
                        label: '#$t',
                        background:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        foreground:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

/// 作者可见的审核状态徽章（对齐网页版 `status_badge`）：
/// 审核中 / 已通过 / 已拒绝 + 已隐藏。普通访客不展示。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    late final Color bg;
    late final Color fg;
    final label = switch (detail.status) {
      'approved' => '已通过',
      'rejected' => '已拒绝',
      _ => '审核中',
    };
    if (detail.status == 'approved') {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (detail.status == 'rejected') {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else {
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    }
    chips.add(_Chip(label: label, background: bg, foreground: fg));

    if (detail.isHidden) {
      chips.add(_Chip(
        label: '已隐藏',
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ));
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// 内容区块：描边圆角卡片 + 小标题 + 正文。
class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.02,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.7,
                wordSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 作者注释（Author's Note）：作者设置的希望模型始终记住/强调的内容。
///
/// 仅在卡片设置了作者注释时展示；带「注入间隔」提示（0 表示未启用间隔）。
class _AuthorNoteSection extends StatelessWidget {
  const _AuthorNoteSection({required this.note, required this.interval});

  final String note;
  final int interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: <Widget>[
                Icon(Icons.push_pin_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '作者注释',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.02,
                  ),
                ),
                if (interval > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '每 $interval 条注入',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.7,
                wordSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 对话示例：一问一答的气泡列表。
class _DialogueSection extends StatelessWidget {
  const _DialogueSection({required this.name, required this.dialogue});

  final String name;
  final List<DialogueTurn> dialogue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.forum_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '对话示例',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.02,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final turn in dialogue) ...[
            if (turn.user.isNotEmpty)
              _ChatBubble(
                alignLeft: false,
                text: turn.user,
                bubbleColor: scheme.primaryContainer,
                textColor: scheme.onPrimaryContainer,
              ),
            if (turn.assistant.isNotEmpty)
              _ChatBubble(
                alignLeft: true,
                text: turn.assistant,
                bubbleColor: scheme.surfaceContainerHighest,
                textColor: scheme.onSurface,
                avatarLabel: name.isNotEmpty ? name[0] : 'AI',
              ),
          ],
        ],
      ),
    );
  }
}

/// 单个对话气泡。
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.alignLeft,
    required this.text,
    required this.bubbleColor,
    required this.textColor,
    this.avatarLabel,
  });

  final bool alignLeft;
  final String text;
  final Color bubbleColor;
  final Color textColor;
  final String? avatarLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(alignLeft ? 4 : 16),
          bottomRight: Radius.circular(alignLeft ? 16 : 4),
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          height: 1.5,
        ),
      ),
    );

    final avatar = avatarLabel != null
        ? CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              avatarLabel!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: alignLeft
            ? <Widget>[
                if (avatar != null) ...[avatar, const SizedBox(width: 8)],
                Flexible(child: bubble),
              ]
            : <Widget>[
                Flexible(child: bubble),
              ],
      ),
    );
  }
}

/// 小胶囊标签（性别/作者/日期/标签）。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// 加载骨架：顶栏返回 + 封面 + 资料/文字条，带 shimmer。
class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({this.leading});

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.surfaceContainerHighest;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          leading: leading,
        ),
        SliverToBoxAdapter(
          child: Shimmer(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 140,
                              height: 18,
                              decoration: BoxDecoration(
                                color: block,
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: 200,
                              height: 14,
                              decoration: BoxDecoration(
                                color: block,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 80,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 错误态：顶栏返回 + 提示 + 重试。
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.leading,
    required this.error,
    required this.onRetry,
  });

  final Widget? leading;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          leading: leading,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.cloud_off_outlined, size: 40, color: scheme.outline),
                  const SizedBox(height: 8),
                  const Text('加载失败'),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}



/// 举报底部表单：选择原因（可选补充说明）后提交。
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.reasons, required this.onSubmitted});

  final List<({String key, String label})> reasons;
  final void Function(String key, String detail) onSubmitted;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _selected;
  final TextEditingController _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '举报角色卡',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final r in widget.reasons)
                        InkWell(
                          onTap: () => setState(() => _selected = r.key),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  _selected == r.key
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 20,
                                  color: _selected == r.key
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Text(r.label),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '补充说明（可选）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () =>
                        widget.onSubmitted(_selected!, _detailCtrl.text.trim()),
                child: const Text('提交举报'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
