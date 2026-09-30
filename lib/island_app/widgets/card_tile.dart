import 'package:flutter/material.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';

/// 单张角色卡组件：封面 + 名称 + 作者 + 简介 + 观看/复制数。
///
/// 输入为卡片摘要 Map（含 id/name/intro/view_count/copy_count/covers/author）。
/// 默认点按打开内置角色卡详情页（[CardDetailPage]）；如需外壳承载或自定义行为，
/// 可传入 [onTap] 覆盖。
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.card, this.onTap});

  final Map<String, dynamic> card;

  /// 点按回调；为 null 时默认 push 内置角色卡详情页。
  final VoidCallback? onTap;

  /// 默认入口：打开内置详情页（而非外链网页）。
  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CardDetailPage(cardId: (card['id'] ?? '').toString()),
      ),
    );
  }

  /// 取第一张封面（covers 是 {slot: path} 的 Map）。
  String? _cover() {
    final covers = card['covers'];
    if (covers is Map && covers.isNotEmpty) {
      final first = covers.values.first;
      if (first is String && first.isNotEmpty) return first;
    }
    return null;
  }

  /// 作者昵称（回退到用户名）。
  String _authorName() {
    final author = card['author'];
    if (author is Map) {
      final nickname = (author['nickname'] ?? '').toString();
      final username = (author['username'] ?? '').toString();
      return nickname.isNotEmpty ? nickname : username;
    }
    return '';
  }

  String _str(String key) => (card[key] ?? '').toString();

  /// 观看/复制数格式化：≥1 万显示 x.x万，≥1 千显示 x.xk。
  String _fmtCount(dynamic v) {
    final n = v is num ? v.toDouble() : 0;
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _str('name');
    final gender = _str('gender');
    final author = _authorName();
    final intro = _str('intro');
    final cover = _cover();

    final metaStyle = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap ?? () => _openDetail(context),
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusMd),
            child: AspectRatio(
              aspectRatio: kCardAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  cover != null
                      ? FadeInNetworkImage(
                          url: ServerConfig.resolveUrl(cover),
                          fit: BoxFit.cover,
                          // 按卡片实际尺寸解码，避免加载原图导致卡顿/内存占用。
                          cacheWidth: 480,
                          placeholder: _placeholder(context),
                        )
                      : _placeholder(context),
                  // 置顶角标：作者把该卡置顶到了主页最前（字段来自 /api/v1 的 pinned）。
                  if (card['pinned'] == true)
                    const Positioned(top: 6, right: 6, child: _PinBadge()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 名称 + 性别同一行，避免单行信息量过低。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (gender.isNotEmpty) ...[
                const SizedBox(width: 6),
                _GenderBadge(gender),
              ],
            ],
          ),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              intro,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          // 统计（观看/复制）与作者同一行，作者靠右。
          Row(
            children: <Widget>[
              Icon(Icons.visibility_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(_fmtCount(card['view_count']), style: metaStyle),
              const SizedBox(width: 12),
              Icon(Icons.content_copy,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(_fmtCount(card['copy_count']), style: metaStyle),
              const Spacer(),
              if (author.isNotEmpty)
                Flexible(
                  child: Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: metaStyle,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

/// 「置顶」角标：覆盖在封面上，标识作者置顶的卡。
class _PinBadge extends StatelessWidget {
  const _PinBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '置顶',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onInverseSurface,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// 性别小徽标：紧凑的圆角标签，显示在名称右侧。
class _GenderBadge extends StatelessWidget {
  const _GenderBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
      ),
    );
  }
}
