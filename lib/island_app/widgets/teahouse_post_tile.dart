import 'package:material_ui/material_ui.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/teahouse_topics_page.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/user_badge.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';
import 'package:dna/island_app/widgets/image_viewer.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';
import '../../theme/tokens.dart';

/// 茶馆帖子卡片（Feed / 收藏 / 话题 / 搜索结果共用）。
///
/// 展示作者头像昵称、正文、配图、关联角色卡、话题、点赞/收藏/回复统计。
/// 点击整卡通过 [onTap] 打开帖子详情；配图点击可全屏放大预览；
/// 点赞/收藏通过 [onLike]/[onFavorite] 直接切换（无需进入详情页）。
class TeahousePostTile extends StatelessWidget {
  const TeahousePostTile({
    super.key,
    required this.post,
    required this.onTap,
    this.onAuthorTap,
    this.onCardTap,
    this.onLike,
    this.onFavorite,
    this.trailing,
  });

  final TeaPost post;
  final VoidCallback onTap;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onCardTap;

  /// 点赞/取消点赞（在卡片上直接切换，不用进详情页）。
  final VoidCallback? onLike;

  /// 收藏/取消收藏（在卡片上直接切换，不用进详情页）。
  final VoidCallback? onFavorite;

  /// 卡片尾部（如「收藏」状态角标），可为空。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = post.author;
    final authorName = author?.displayName ?? '未知用户';
    final imageUrl = post.image?.url ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        // 行间距（版心仍由页面 wideInset + 这里的横向 16 共同决定）。
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(AppSpacing.md),
        // 去掉 1px 描边：页面底色本身就是 surface，那根线只是「看得见的分界」，
        // 不是层级语言。层级改由 surfaceContainerLow 承担（审计 3.3：
        // 帖子流每行是「描边 + 同色底」，只能靠线分界）。
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 作者行。
            InkWell(
              onTap: onAuthorTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Avatar(avatar: author?.avatar ?? '', radius: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          UserBadge(
                            name: authorName,
                            isSponsor: author?.isSponsor == true,
                            verified: author?.verified == true,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (post.createdAt.isNotEmpty)
                            Text(
                              formatRelativeTime(post.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 正文（长文可就地展开/收起）。
            _ExpandableContent(content: post.content),
            // 配图（点击全屏放大预览）。
            if (imageUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              // 配图可点开大图：用 InkWell + 语义，而不是裸 GestureDetector ——
              // 裸手势没有涟漪、没有焦点、读屏也不知道这里能点（审计 4.3）。
              // Material(transparency) 只是给涟漪一个落脚面：图片本身不透明，
              // 直接套 InkWell 的话水波纹会被图片盖住，看不见反馈。
              Semantics(
                button: true,
                label: '查看大图',
                child: Material(
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ImageViewerPage.open(
                      context,
                      urls: <String>[ServerConfig.resolveUrl(imageUrl)],
                    ),
                    child: Image.network(
                      ServerConfig.resolveUrl(imageUrl),
                      fit: BoxFit.cover,
                      // 贴在列表里只有 160 高，按屏宽限宽解码即可（原图常见 1080+）。
                      cacheWidth: (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context) *
                              0.5)
                          .clamp(240, 960)
                          .round(),
                      height: 160,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : const SizedBox(height: 160),
                    ),
                  ),
                ),
              ),
            ],
            // 关联角色卡。
            if (post.card != null) ...<Widget>[
              const SizedBox(height: 8),
              _CardLinkChip(card: post.card!, onTap: onCardTap),
            ],
            // 话题。
            if (post.stats.topics.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: post.stats.topics.map((t) {
                  // 话题是一个**目的地**（TeahouseTopicPage 早就存在），不是
                  // 「点了报个名字」的装饰。这里用 ActionChip：自带涟漪、
                  // 按钮语义（读屏会念「#话题，按钮」）与 ≥48dp 命中区
                  // （审计 3.5：以前只弹一条 1 秒 snackbar）。
                  return ActionChip(
                    label: Text('#${t.name}'),
                    onPressed: () => _openTopic(context, t),
                    backgroundColor: scheme.surfaceContainerHighest,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 8),
            // 统计行（点赞/收藏可直接点击切换，评论打开详情）。
            _StatsRow(
              post: post,
              onLike: onLike,
              onFavorite: onFavorite,
              onComment: onTap,
            ),
          ],
        ),
      ),
    );
  }

  void _openTopic(BuildContext context, TeaPostTopic topic) {
    // 直接进话题页：点话题的预期就是「看这个话题下的帖子」，
    // 而不是先被告知话题叫什么（审计 3.5，A 级）。
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahouseTopicPage(
          topicId: int.tryParse(topic.id) ?? 0,
          topicName: topic.name,
        ),
      ),
    );
  }
}

/// 关联角色卡小卡片：封面 + 名称 + 打开图标，点击进入对应卡详情。
class _CardLinkChip extends StatelessWidget {
  const _CardLinkChip({required this.card, this.onTap});

  final TeaPostCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = card.cover;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: AppAlpha.a40),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipOval(
              child: SizedBox(
                width: 22,
                height: 22,
                child: cover.isNotEmpty
                    ? FadeInNetworkImage(
                        url: ServerConfig.resolveUrl(cover),
                        fit: BoxFit.cover,
                        cacheWidth: 64,
                        placeholder: _coverPlaceholder(scheme),
                      )
                    : _coverPlaceholder(scheme),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new, size: 13, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.primaryContainer.withValues(alpha: AppAlpha.a40),
      child: Center(
        child: Icon(Icons.badge_outlined, size: 13, color: scheme.primary),
      ),
    );
  }
}

/// 点赞 / 收藏 / 回复 统计行。
///
/// 点赞与收藏可点击直接切换（无需进详情页）；评论点击打开详情页。
///
/// 三个动作都保证 **≥48dp 命中盒**：原来是手搓 InkWell + 4/2 内边距，
/// 整个可点区域约 21×23，只有 M3 最小触摸目标的四分之一；而且没有标签，
/// 读屏念出来只是一个孤零零的数字（审计 4.3）。
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.post,
    this.onLike,
    this.onFavorite,
    this.onComment,
  });

  final TeaPost post;
  final VoidCallback? onLike;
  final VoidCallback? onFavorite;
  final VoidCallback? onComment;

  /// 统计行是**密集控件**：一行三颗、行高由这一行决定，所以不套 48dp 命中盒
  /// （48 是命中盒不是视觉尺寸；硬套会把每条帖子撑高约一倍）。
  /// 尺寸回到原实现：图标 17 + Padding(horizontal: 4, vertical: 2) ⇒ 行高约 21。
  /// 见 docs/REGRESSION_AUDIT.md 与 DESIGN_SPEC「密集控件例外」。

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = post.stats;
    return Row(
      children: <Widget>[
        _countAction(
          context,
          icon: stats.liked ? Icons.favorite : Icons.favorite_border,
          count: stats.likeCount,
          semanticLabel: stats.liked
              ? '取消点赞，当前 ${stats.likeCount}'
              : '点赞，当前 ${stats.likeCount}',
          // 「已赞」是**选中态**，不是错误：这个 App 里 error 还表示
          // 「处罚生效中」，拿它标喜欢在语义上会打架（审计 4.1）。
          color: stats.liked ? scheme.primary : scheme.onSurfaceVariant,
          onTap: onLike,
        ),
        AppSpacing.wMd,
        _countAction(
          context,
          icon: Icons.chat_bubble_outline,
          count: stats.replyCount,
          semanticLabel: '查看 ${stats.replyCount} 条评论',
          onTap: onComment,
        ),
        AppSpacing.wMd,
        // 收藏是**二值状态**：填充/描边图标已经表达完了，不再伪造一个 0/1
        // 计数（审计 3.5：布尔状态不该伪装成计数）。
        _iconAction(
          context,
          icon: stats.favorited ? Icons.bookmark : Icons.bookmark_border,
          semanticLabel: stats.favorited ? '取消收藏' : '收藏',
          // 与「已赞」同一条规则：已选中 = primary。
          color: stats.favorited ? scheme.primary : scheme.onSurfaceVariant,
          onTap: onFavorite,
        ),
      ],
    );
  }

  /// 图标 + 计数（点赞 / 评论）。
  Widget _countAction(
    BuildContext context, {
    required IconData icon,
    required int count,
    required String semanticLabel,
    Color? color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _actionBox(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: AppSize.iconCard,
            color: color ?? scheme.onSurfaceVariant,
          ),
          AppSpacing.wXs,
          Text('$count', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  /// 纯图标动作（收藏，无计数）。
  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required String semanticLabel,
    Color? color,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _actionBox(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Icon(
        icon,
        size: AppSize.iconCard,
        color: color ?? scheme.onSurfaceVariant,
      ),
    );
  }

  /// 涟漪 + 语义标签（保留）；尺寸走原实现的密集行内边距。
  Widget _actionBox({
    required String semanticLabel,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      // 图标/数字不再单独念一遍，避免「3」这种没主语的碎片。
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 帖子正文：超过阈值默认折叠为 6 行，可「展开全文/收起」（对齐网页版 >200 字折叠）。
class _ExpandableContent extends StatefulWidget {
  const _ExpandableContent({required this.content});

  final String content;

  @override
  State<_ExpandableContent> createState() => _ExpandableContentState();
}

class _ExpandableContentState extends State<_ExpandableContent> {
  bool _expanded = false;

  /// 网页版折叠阈值：超过 200 字才折叠。
  bool get _isLong => widget.content.length > 200;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final long = _isLong;
    final expanded = _expanded && long;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StickerText(
          widget.content,
          maxLines: expanded ? null : 6,
          overflow: expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: AppLineHeight.body,
          ),
        ),
        if (long)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                expanded ? '收起' : '展开全文',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
