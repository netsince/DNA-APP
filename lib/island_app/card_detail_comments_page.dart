part of 'card_detail_page.dart';

/// 角色卡评论区（独立页）。
///
/// 列表、排序、楼中楼回复与底部输入条全部由共享的 [CommentSection] 提供；
/// 本页只负责两件 CommentSection 自己不做的事：给它一个**有界高度**的宿主、
/// 以及一条正常的返回路径（[AppBar] 的返回键 / 系统返回）。
///
/// 这正是它以前借 0.9 屏 bottom sheet 干的事 —— 区别只在于：现在它是一个页，
/// 而不是一个「看起来像页的弹层」（审计 3.2）。
class _CommentsPage extends StatelessWidget {
  const _CommentsPage({
    required this.cardId,
    required this.cardTitle,
    required this.isLoggedIn,
    required this.isOwner,
    this.focusCommentId,
  });

  final String cardId;

  /// 标题用角色卡名：用户在评论页也能一眼看出这是哪张卡的评论区。
  final String cardTitle;

  final bool? isLoggedIn;
  final bool? isOwner;
  final int? focusCommentId;

  @override
  Widget build(BuildContext context) {
    final String rawTitle = cardTitle.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          rawTitle.isEmpty ? '评论' : rawTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // SafeArea 只保底部：输入条贴着系统导航条，不能压在它下面。
      body: SafeArea(
        top: false,
        child: CommentSection(
          cardId: cardId,
          isLoggedIn: isLoggedIn,
          isOwner: isOwner,
          focusCommentId: focusCommentId,
        ),
      ),
    );
  }
}
