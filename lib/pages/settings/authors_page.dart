import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/widgets/fit_text.dart';

/// 参与人员信息条目。
class _Author {
  const _Author({
    required this.name,
    this.role,
    this.aliases,
    this.website,
  });

  final String name;

  /// 分工说明；为空表示不标注分工。
  final String? role;

  /// 别名列表；为空表示无别名。
  final List<String>? aliases;

  /// 个人网站；为空表示无个人网站。
  final String? website;
}

/// 参与人员与分工。分工、别名、个人网站由各参与人员提供。
const List<_Author> _kAuthors = <_Author>[
  _Author(
    name: 'netSince.com',
    website: 'netsince.com',
  ),
  _Author(
    name: 'Yang Borui',
    role: '开发 · 社区运营',
    aliases: <String>['Roko', 'AIXIAOJI'],
    website: 'roko.nb6.ltd',
  ),
  _Author(
    name: '太空虎设计',
    role: '软件 LOGO 设计',
  ),
  _Author(
    name: '终LFFX',
    role: '前期社区搭建',
    website: 'https://dnaisland.nb6.ltd/user/终',
  ),
  _Author(
    name: '辞安',
    role: '前期社区搭建',
    website: 'https://dnaisland.nb6.ltd/user/辞安',
  ),
  _Author(
    name: 'zwqq',
    role: '前期社区搭建',
    aliases: <String>['byz0225'],
    website: 'https://dnaisland.nb6.ltd/user/byz0225',
  ),
  _Author(
    name: '问问',
    role: '前期社区搭建',
    website: 'https://dnaisland.nb6.ltd/user/2933376189@qq.com',
  ),
  _Author(
    name: '晨霧',
    role: '前期社区搭建',
    website: 'https://dnaisland.nb6.ltd/user/Chengwu',
  ),
  _Author(
    name: '人r',
    role: '第三个看板娘图标绘制',
    website: 'https://dnaisland.nb6.ltd/user/人R',
  ),
];

/// 参与人员名单页：展示每位参与人员的名称、分工、别名与个人网站。
class AuthorsPage extends StatelessWidget {
  const AuthorsPage({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final String target = url.startsWith('http') ? url : 'https://$url';
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('无法打开链接：$target')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('参与人员名单')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                children: <Widget>[
                  for (final a in _kAuthors) ...[
                    _AuthorCard(
                      author: a,
                      onTap: a.website == null
                          ? null
                          : () => _open(context, a.website!),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuthorCard extends StatelessWidget {
  const _AuthorCard({required this.author, this.onTap});

  final _Author author;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 名称 + 分工
              FitText(
                author.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (author.role != null && author.role!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Icon(Icons.workspace_premium_outlined,
                        size: 13, color: cs.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FitText(
                        author.role!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              // 别名、个人网站（仅存在时显示）
              if (author.aliases != null && author.aliases!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _metaRow(
                  context,
                  icon: Icons.alternate_email,
                  text: author.aliases!.join(' · '),
                ),
              ],
              if (author.website != null && author.website!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                _metaRow(
                  context,
                  icon: Icons.language,
                  text: author.website!,
                  isLink: onTap != null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context,
      {required IconData icon, required String text, bool isLink = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: isLink ? cs.primary : cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: FitText(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isLink ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: isLink ? FontWeight.w500 : null,
                ),
          ),
        ),
        if (isLink) Icon(Icons.open_in_new, size: 13, color: cs.primary),
      ],
    );
  }
}
