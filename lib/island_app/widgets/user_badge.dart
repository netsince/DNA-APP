import 'package:flutter/material.dart';

/// 用户名 + 装饰徽章：**赞助红星** + 认证徽章。
///
/// 对齐网页版的 `templates/macros/user_badge.html`（昵称 + 红星 + 认证）。
/// 收敛成一个组件的原因：这两个标记散落在个人页 / 卡片详情 / 茶馆 / 评论 /
/// 关注列表 / 搜索等 8 处，各画一遍的话改一次样式要满仓库找。
///
/// 数据来源：API `_user_public()` 输出的 `nickname` / `verified` /
/// `verified_label` / `is_sponsor`。字段缺失（旧服务端）一律按"无标记"处理，
/// 所以两端可以分别上线。
class UserBadge extends StatelessWidget {
  const UserBadge({
    super.key,
    required this.name,
    this.isSponsor = false,
    this.verified = false,
    this.verifiedLabel = '',
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.badgeSize = 14,
  });

  /// 从 API 的用户 map 构造（`_user_public()` 的形状）。
  ///
  /// 昵称优先，其次用户名；两者都空时用 [fallbackName]。
  factory UserBadge.fromUser(
    Map<String, dynamic>? user, {
    Key? key,
    String fallbackName = '',
    TextStyle? style,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    final String nickname = (user?['nickname'] ?? '').toString();
    final String username = (user?['username'] ?? '').toString();
    final String name = nickname.isNotEmpty
        ? nickname
        : (username.isNotEmpty ? username : fallbackName);
    return UserBadge(
      key: key,
      name: name,
      isSponsor: user?['is_sponsor'] == true,
      verified: user?['verified'] == true,
      verifiedLabel: (user?['verified_label'] ?? '').toString(),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  final String name;

  /// 赞助者：昵称后一颗红星（网页版 `bi-star-fill text-danger`）。
  final bool isSponsor;

  final bool verified;
  final String verifiedLabel;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  /// 徽章图标尺寸：列表/卡片用 14，个人页等大字号处可调大（原来是 18）。
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget badges = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            name,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          ),
        ),
        if (isSponsor) ...<Widget>[
          const SizedBox(width: 4),
          Tooltip(
            message: '赞助者',
            child: Icon(Icons.star, size: badgeSize, color: scheme.error),
          ),
        ],
        if (verified) ...<Widget>[
          const SizedBox(width: 4),
          Icon(Icons.verified, size: badgeSize, color: scheme.primary),
        ],
      ],
    );
    if (!verified || verifiedLabel.trim().isEmpty) {
      return badges;
    }
    // 认证名称（如「官方认证」）放在悬停提示里，对齐网页版的 title 属性。
    return Tooltip(message: verifiedLabel, child: badges);
  }
}
