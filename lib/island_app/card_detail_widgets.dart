part of 'card_detail_page.dart';

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
      borderRadius: BorderRadius.circular(AppRadius.md),
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
    // 可点的头图：补「按钮」语义与标签，读屏才知道这里能点开大图
    // （审计 4.3：裸 GestureDetector 承担可点区域，无语义无反馈）。
    return Semantics(
      button: true,
      label: '查看大图',
      child: GestureDetector(
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
                color: scheme.surface.withValues(alpha: AppAlpha.mutedStrong),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.zoom_in, size: 14, color: scheme.onSurface),
                  const SizedBox(width: 4),
                  Text(
                    '查看原图',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

  String _shortDate(String iso) {
    if (iso.length >= 10) return iso.substring(0, 10);
    return iso;
  }

  Widget _avatar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarPath = detail.avatarPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
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
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
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

    // 元信息标签统一走共享的只读 StatusBadge（不可点的信息不做成 chip 外观）。
    final chips = <Widget>[
      if (detail.gender.isNotEmpty)
        StatusBadge(
          // 服务端存的是 ID（历史中文值）；未知值原样显示，不丢数据。
          label: TaGender.labelOf(detail.gender),
          tone: BadgeTone.positive,
        ),
      if (detail.authorName != null && detail.authorName!.isNotEmpty)
        StatusBadge(
          label: detail.authorName!,
          icon: Icons.person_outline,
        ),
      if (detail.createdAt.isNotEmpty)
        StatusBadge(
          label: _shortDate(detail.createdAt),
          icon: Icons.calendar_today_outlined,
        ),
      if (detail.updatedAt.isNotEmpty &&
          _shortDate(detail.updatedAt) != _shortDate(detail.createdAt))
        StatusBadge(
          label: '更新 ${_shortDate(detail.updatedAt)}',
          icon: Icons.update_outlined,
        ),
    ];

    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    // 统计：浏览 / 复制，居中或居左随布局变化。
    final stats = Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.visibility_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(formatCount(detail.viewCount), style: metaStyle),
        const SizedBox(width: 20),
        Icon(Icons.content_copy, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(formatCount(detail.copyCount), style: metaStyle),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: AppInsets.card,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: centered
          ? Column(
              children: <Widget>[
                _avatar(context),
                const SizedBox(height: 12),
                Text(
                  detail.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 6, children: chips),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = nickname.isNotEmpty ? nickname : username;

    final card = Container(
      padding: AppInsets.card,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                value: cardCount == null ? '…' : formatCount(cardCount!),
              ),
              const SizedBox(width: 24),
              _AuthorStat(
                icon: Icons.people_outline,
                label: '粉丝',
                value: followerCount == null ? '…' : formatCount(followerCount!),
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
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTapAuthor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: card,
          ),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: card);
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
      final int target =
          (radius * 2 * MediaQuery.devicePixelRatioOf(context))
              .clamp(32, 256)
              .round();
      final ImageProvider? provider =
          MemoImage.dataUrl(a, cacheWidth: target);
      child = provider == null
          ? Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant)
          : Image(
              image: provider,
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
        child: SizedBox(width: radius * 2, height: radius * 2, child: child),
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
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
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
                // 「已赞」是**选中态**不是错误：error 在这个 App 里表示
                // 「处罚生效中」这类真错误，拿它标喜欢语义会打架（审计 4.1）。
                // 与「已收藏」同一条规则：已选中 = primary。
                foregroundColor: detail.liked ? scheme.primary : null,
                backgroundColor: detail.liked
                    ? scheme.primaryContainer
                    : null,
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
                backgroundColor: detail.favorited
                    ? scheme.primaryContainer
                    : null,
              ),
              child: Text('${detail.favoriteCount}'),
            ),
          ),
          const SizedBox(width: 12),
          // 主按钮：**导入到本地**（社区嵌主应用时）；复制挪进「⋯」菜单。
          // 没有本地库可写时（独立运行）退回原来的复制按钮。
          if (page._importer != null)
            AsyncActionButton(
              variant: AsyncButtonVariant.tonal,
              tooltip: '导入到本地',
              onPressed: page._importCard,
              icon: const Icon(Icons.download_outlined, size: 18),
              loadingSize: 18,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHigh,
                foregroundColor: scheme.onSurfaceVariant,
                // 密集控件（一行四颗，行高由这一行决定）：回到原实现的 40dp
                // 视觉尺寸；48 是命中盒不是视觉尺寸，硬套会让操作条高一圈。
                visualDensity: VisualDensity.compact,
                minimumSize: const Size.square(40),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          else
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
                // 密集控件（一行四颗，行高由这一行决定）：回到原实现的 40dp
                // 视觉尺寸；48 是命中盒不是视觉尺寸，硬套会让操作条高一圈。
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
                  .map((t) => StatusBadge(label: '#$t'))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

/// 作者可见的审核状态徽章（对齐网页版 `status_badge`）：
/// 审核中 / 已通过 / 已拒绝 + 已隐藏。普通访客不展示。
///
/// 只是把 detail.status 映射成共享 [StatusBadge] 的色调 —— 视觉（主色/错误色/
/// 第三色）与原来一致，实现不再自绘容器。
class _ReviewStatusBadges extends StatelessWidget {
  const _ReviewStatusBadges({required this.detail});

  final CardDetail detail;

  @override
  Widget build(BuildContext context) {
    final (String label, BadgeTone tone) = switch (detail.status) {
      'approved' => ('已通过', BadgeTone.positive),
      'rejected' => ('已拒绝', BadgeTone.danger),
      _ => ('审核中', BadgeTone.caution),
    };
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        StatusBadge(label: label, tone: tone, semanticLabel: '审核状态：$label'),
        if (detail.isHidden)
          const StatusBadge(label: '已隐藏', semanticLabel: '审核状态：已隐藏'),
      ],
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
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
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
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: AppAlpha.a35),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: AppLineHeight.reading,
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
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: AppInsets.card,
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
          height: AppLineHeight.body,
        ),
      ),
    );

    final avatar = avatarLabel != null
        ? CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              avatarLabel!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppFontSize.caption,
              ),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: alignLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: alignLeft
            ? <Widget>[
                if (avatar != null) ...[avatar, const SizedBox(width: 8)],
                Flexible(child: bubble),
              ]
            : <Widget>[Flexible(child: bubble)],
      ),
    );
  }
}

// 小标签（性别 / 作者 / 日期 / 标签 / 审核状态）统一走共享 StatusBadge：
// 只读指示、语义色调、无 ink。原来这里有一份自绘的 _Chip（按 raw color 传参）。
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
              padding: AppInsets.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    height: 220,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
                          borderRadius: BorderRadius.circular(AppRadius.lg),
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: 200,
                              height: 14,
                              decoration: BoxDecoration(
                                color: block,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
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
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
        // 内容块改用共享三态：以前这里手写「图标 + 加载失败 + 原因 + 重试」，
        // 与全站 ErrorState 平行（图标尺寸、按钮样式各写一遍）。
        // 说明文字直接用失败原因：『加载失败』做标题、原因做副文案是两层表达，
        // 而用户真正要看的是原因。
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: AppErrorState(message: error, onRetry: onRetry),
          ),
        ),
      ],
    );
  }
}

