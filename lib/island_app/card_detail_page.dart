import 'dart:convert';
import '../widgets/memo_image.dart';

import 'package:material_ui/material_ui.dart';

import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/ta_gender.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/teahouse_compose_page.dart';
import 'package:dna/island_app/utils/auth_guard.dart';
import 'package:dna/island_app/widgets/report_sheet.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/utils/count_format.dart';
import 'package:dna/island_app/widgets/async_action_button.dart';
import 'package:dna/island_app/widgets/comment_section.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';
import 'package:dna/island_app/widgets/image_viewer.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/status_badge.dart';
import 'package:dna/island_app/widgets/user_badge.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/utils/action_table.dart';
import '../theme/tokens.dart';
import '../widgets/detail_section.dart';

part 'card_detail_widgets.dart';
part 'card_detail_comments_page.dart';

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
      authorName = ((author['nickname'] ?? '').toString().isNotEmpty)
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
          dialogue.add(
            DialogueTurn(
              user: (turn['user'] ?? '').toString(),
              assistant: (turn['assistant'] ?? '').toString(),
            ),
          );
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
      viewCount: (m['view_count'] is num)
          ? (m['view_count'] as num).toInt()
          : 0,
      copyCount: (m['copy_count'] is num)
          ? (m['copy_count'] as num).toInt()
          : 0,
      likeCount: (m['like_count'] is num)
          ? (m['like_count'] as num).toInt()
          : 0,
      favoriteCount: (m['favorite_count'] is num)
          ? (m['favorite_count'] as num).toInt()
          : 0,
      commentCount: (m['comment_count'] is num)
          ? (m['comment_count'] as num).toInt()
          : 0,
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
      authorNoteInterval: (m['authorNoteInterval'] is num)
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
      bannerPath != null &&
      coverFocus.trim().isNotEmpty &&
      coverFocus.contains(',');

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
///
/// **必须与 [ApiClient.submitReport] 的形参形式一致（都用命名参数）**：
/// 两者不一致时 `widget.reportSubmitter ?? ApiClient.instance.submitReport`
/// 的类型会退化成 `Function`，编译期不报错、调用时才抛 NoSuchMethodError ——
/// 举报就这么坏过一次（调用处传位置参数，实现却只收命名参数）。
typedef ReportSubmitter =
    Future<void> Function({
      required String type,
      required String id,
      required String reason,
      String? detail,
    });

/// 复制/导出角色卡：返回可写入剪贴板的角色卡 JSON 包字符串（需登录）。
typedef CardExporter = Future<String> Function(String cardId);

/// 「直接导入到本地」回调：把社区角色卡解析后落进本地库（id 由实现方重新生成）。
typedef CardImporter = Future<String> Function(TA ta);

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
    this.cardImporter,
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

  /// 「直接导入到本地」；为 null 时导入入口隐藏（独立运行/旧调用方）。
  final CardImporter? cardImporter;

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
    } catch (e) {
      _showSnack('操作失败：${describeError(e)}');
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
      final writer =
          widget.clipboardWriter ??
          (text) => Clipboard.setData(ClipboardData(text: text));
      await writer(pkg);
      if (!mounted) return;
      _showSnack('已复制角色卡内容');
    } catch (e) {
      if (!mounted) return;
      _showSnack('复制失败：${describeError(e)}');
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  /// 导入回调的快捷读取（供 action 区判断主按钮形态）。
  CardImporter? get _importer => widget.cardImporter;

  /// 直接导入到本地角色卡库。
  ///
  /// 走与「复制」**同一个**导出接口（复制量照常 +1、留溯源记录），
  /// 再解析 JSON 包落进本地库（id 由主应用重新生成）。没有本地库可写时
  /// （cardImporter 为 null）不显示这个入口。
  Future<void> _importCard() async {
    if (!_loggedIn) {
      AuthGuard.require(context, message: '请先登录后再导入');
      return;
    }
    final CardImporter? importer = widget.cardImporter;
    if (importer == null) {
      _showSnack('当前环境不支持导入');
      return;
    }
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final exporter = widget.cardExporter ?? ApiClient.instance.exportCard;
      final pkg = await exporter(widget.cardId);
      final parsed = TaExportImportService.importCharacter(pkg);
      TA? ta = parsed.data?.ta;
      if (ta == null) {
        if (!mounted) return;
        _showSnack(parsed.message ?? '无法识别这份角色卡');
        return;
      }
      // 把导出包里的内嵌图片逐槽落到本地存储 —— toTA() 出来的 images 是空的，
      // 不补这一步导入进来的卡就没图（编辑器的导入流程也是这么做的）。
      final ExportImportResult<TA> restored =
          await TaExportImportService.restoreTaImages(
            ta,
            jsonDecode(pkg) as Map<String, dynamic>,
          );
      if (restored.success && restored.data != null) {
        ta = restored.data;
      }
      if (ta == null) {
        _showSnack('导入失败，请重试');
        return;
      }
      await importer(ta);
      if (!mounted) return;
      _showSnack('已导入到本地角色卡：${ta.name}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('导入失败：${describeError(e)}');
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
      final writer =
          widget.clipboardWriter ??
          (text) => Clipboard.setData(ClipboardData(text: text));
      await writer(url);
      if (!mounted) return;
      _showSnack('已复制网页链接');
    } catch (e) {
      if (!mounted) return;
      _showSnack('复制失败：${describeError(e)}');
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
        builder: (_) =>
            TeahouseComposePage(presetCardId: d.id, presetCardName: d.name),
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
    } catch (e) {
      if (!mounted) return;
      _showSnack('操作失败：${describeError(e)}');
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

  /// 打开评论区：**一条真实路由**，而不是弹层。
  ///
  /// 评论是这张卡的**主要内容**，不是补充动作。以前它是 0.9 屏高的 modal
  /// bottom sheet —— 那等于「伪装成页面的页面」：压在详情页之上、多一层路由、
  /// 返回要退两段、链接与分享都拿不到（审计 3.2）。
  ///
  /// 为什么不内联成详情页里的一个 section：`CommentSection` 的契约是
  /// 「列表占满剩余高度 + 输入条钉在底部」（内部 `Expanded`），它**必须有界高度**；
  /// 塞进详情页的滚动流就会变成「页面里再套一个滚动区」，比原来的 sheet 更难用。
  /// 所以给它一个独立页 —— 输入条照样钉在底部，只是外面多了一层正常的返回。
  void _openComments() {
    final d = _detail;
    if (d == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CommentsPage(
          cardId: widget.cardId,
          cardTitle: d.name,
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
        _authorNickname = nickname.isEmpty
            ? _detail!.authorName ?? ''
            : nickname;
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
    } catch (e) {
      _showSnack('操作失败：${describeError(e)}');
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
    showSnack(context, msg);
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
        ImageViewerPage.open(
          context,
          urls: <String>[ServerConfig.resolveUrl(banner)],
        );
      }
      return;
    }
    final urls = images.values.map((p) => ServerConfig.resolveUrl(p)).toList();
    final resolvedTarget = targetUrl != null
        ? ServerConfig.resolveUrl(targetUrl)
        : null;
    final initialIndex = resolvedTarget != null
        ? urls.indexOf(resolvedTarget)
        : 0;
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
      builder: (_) => ReportSheet(
        title: '举报角色卡',
        reasons: reasons,
        onSubmitted: (key, detail) =>
            Navigator.of(context).pop((key: key, detail: detail)),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      final submit = widget.reportSubmitter ?? ApiClient.instance.submitReport;
      await submit(
        type: 'card',
        id: detailId,
        reason: picked.key,
        detail: picked.detail,
      );
      if (!mounted) return;
      _showSnack('举报已提交，管理员会尽快处理');
    } catch (e) {
      _showSnack('举报提交失败：${describeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody(context));
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
                color: scheme.surface.withValues(alpha: AppAlpha.a92),
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
            // 举报入口（更多菜单）：可见条件（仅作者 / 有本地库可写）与忙碌态
            // （导入中 / 复制中）都写成数据，画法交给共享的 rowActionMenu ——
            // 项内图标 20、间距 12 就是原来手搓 Row 的那两个数字。
            rowActionMenu(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              iconGap: 12,
              actions: <RowAction>[
                RowAction(
                  id: 'toggle_hidden',
                  label: d.isHidden ? '取消隐藏' : '隐藏',
                  icon: d.isHidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  visible: _owner,
                  enabled: !_hiding,
                  onSelected: _toggleHidden,
                ),
                // 直接导入：只在有本地库可写（社区嵌进主应用）时出现。
                RowAction(
                  id: 'import_ta',
                  label: '导入到本地',
                  icon: Icons.download_outlined,
                  visible: widget.cardImporter != null,
                  enabled: !_copying,
                  onSelected: _importCard,
                ),
                // 复制：从主按钮挪进菜单（主位让给「导入到本地」）。
                RowAction(
                  id: 'copy_card',
                  label: '复制卡片',
                  icon: Icons.content_copy,
                  enabled: !_copying,
                  onSelected: _copyCard,
                ),
                RowAction(
                  id: 'copy_link',
                  label: '复制链接',
                  icon: Icons.link,
                  enabled: !_copyingLink,
                  onSelected: _copyCardLink,
                ),
                RowAction(
                  id: 'teahouse',
                  label: '引用到茶馆',
                  icon: Icons.local_cafe_outlined,
                  onSelected: _quoteToTeahouse,
                ),
                RowAction(
                  id: 'report',
                  label: '举报',
                  icon: Icons.flag_outlined,
                  onSelected: _openReport,
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
                  child: _HeroBanner(detail: d, onTap: _openImageViewer),
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
                  statusBadge: _owner ? _ReviewStatusBadges(detail: d) : null,
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
      MaterialPageRoute<void>(builder: (_) => UserProfilePage(username: u)),
    );
  }

  /// 内容区块（简介/人格设定/开场白/对话示例/原始链接），窄屏与宽屏共用。
  ///
  /// [includeTags] 为 true 时包含标签区（窄屏），false 时标签由资料栏展示（宽屏）。
  /// 内容区块：**描述在这里，画法交给共享的 [DetailSections]**。
  ///
  /// 每个区块只声明「有没有内容 / 标题 / 图标 / 自定义 widget」，
  /// 空值自动不占位（以前是一串 if + 手抄包裹）。
  List<Widget> _contentSectionChildren(
    CardDetail d, {
    required bool includeTags,
  }) {
    return <Widget>[
      if (includeTags && (d.tags.isNotEmpty || _owner))
        _TagsSection(
          tags: d.tags,
          statusBadge: _owner ? _ReviewStatusBadges(detail: d) : null,
        ),
      ...DetailSections.buildAll(<DetailSectionSpec>[
        DetailSectionSpec(
          id: 'intro',
          icon: Icons.notes_outlined,
          title: '简介',
          body: d.intro,
        ),
        DetailSectionSpec(
          id: 'persona',
          icon: Icons.badge_outlined,
          title: '人格设定',
          body: d.persona,
        ),
        DetailSectionSpec(
          id: 'opening',
          icon: Icons.chat_bubble_outline,
          title: '开场白',
          // 开场白不做强斜体、不加装饰，保持 MDUI 简洁排版。
          body: d.opening,
        ),
        // 下面三个不是纯文本：对话示例 / 作者注释 / 外链按钮，
        // 用 custom 挂进去，空值时同样自动不占位。
        DetailSectionSpec(
          id: 'dialogue',
          title: '对话示例',
          custom: d.dialogue.isEmpty
              ? null
              : _DialogueSection(name: d.name, dialogue: d.dialogue),
        ),
        DetailSectionSpec(
          id: 'authorNote',
          title: '作者注释',
          custom: (d.authorNote == null || d.authorNote!.isEmpty)
              ? null
              : _AuthorNoteSection(
                  note: d.authorNote!,
                  interval: d.authorNoteInterval,
                ),
        ),
        DetailSectionSpec(
          id: 'originalLink',
          title: '原始链接',
          custom: d.originalLink.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => _openLink(d.originalLink),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('原始链接'),
                  ),
                ),
        ),
      ]),
    ];
  }
}

