import 'package:flutter/material.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';
import 'package:dna/island_app/widgets/image_viewer.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';

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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 作者行。
            InkWell(
              onTap: onAuthorTap,
              borderRadius: BorderRadius.circular(20),
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
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  authorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (author?.verified == true) ...<Widget>[
                                const SizedBox(width: 4),
                                Icon(Icons.verified,
                                    size: 14, color: scheme.primary),
                              ],
                            ],
                          ),
                          if (post.createdAt.isNotEmpty)
                            Text(
                              formatRelativeTime(post.createdAt),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.outline),
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
              GestureDetector(
                onTap: () => ImageViewerPage.open(
                  context,
                  urls: <String>[ServerConfig.resolveUrl(imageUrl)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    ServerConfig.resolveUrl(imageUrl),
                    fit: BoxFit.cover,
                    height: 160,
                    width: double.infinity,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const SizedBox(height: 160),
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
                  return InkWell(
                    onTap: () => _openTopic(context, t.name),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '#${t.name}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
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

  void _openTopic(BuildContext context, String name) {
    // 话题跳转：先提示（Feed 的话题点击仅展示名称，不做跳转，避免额外导航）。
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('话题：#$name'), duration: Duration(seconds: 1)));
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
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
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
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
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      child: Center(
        child: Icon(Icons.badge_outlined, size: 13, color: scheme.primary),
      ),
    );
  }
}

/// 点赞 / 收藏 / 回复 统计行。
///
/// 点赞与收藏可点击直接切换（无需进详情页）；评论点击打开详情页。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = post.stats;
    return Row(
      children: <Widget>[
        _stat(
          context,
          stats.liked ? Icons.favorite : Icons.favorite_border,
          stats.likeCount,
          color: stats.liked ? scheme.error : scheme.onSurfaceVariant,
          onTap: onLike,
        ),
        const SizedBox(width: 18),
        _stat(
          context,
          Icons.chat_bubble_outline,
          stats.replyCount,
          onTap: onComment,
        ),
        const SizedBox(width: 18),
        _stat(
          context,
          stats.favorited ? Icons.bookmark : Icons.bookmark_border,
          stats.favorited ? 1 : 0,
          color: stats.favorited
              ? scheme.tertiary
              : scheme.onSurfaceVariant,
          onTap: onFavorite,
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, IconData icon, int count,
      {Color? color, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 17, color: color ?? scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('$count', style: theme.textTheme.labelMedium),
          ],
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
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        if (long)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
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
