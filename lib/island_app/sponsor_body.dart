import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 赞助页面（无脚手架，由 [RootShell] 承载）。
///
/// 顶部为标题 + 富文本赞助说明（HTML），下方为醒目的「前往赞助」按钮，
/// 以及随机打乱的赞助者列表；点击赞助者可跳转到其主页（按 UID 关联的用户）。
class SponsorBody extends StatefulWidget {
  const SponsorBody({super.key});

  @override
  State<SponsorBody> createState() => _SponsorBodyState();
}

class _SponsorBodyState extends State<SponsorBody> {
  bool _loading = true;
  String? _error;

  bool _enabled = false;
  String _title = '';
  String _content = '';
  String _url = '';
  final List<Map<String, dynamic>> _sponsors = [];

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
      final data = await ApiClient.instance.getSponsors();
      if (!mounted) return;
      setState(() {
        _enabled = data['enabled'] == true;
        _title = (data['title'] ?? '').toString();
        _content = (data['content'] ?? '').toString();
        _url = (data['url'] ?? '').toString();
        _sponsors
          ..clear()
          ..addAll((data['sponsors'] as List? ?? [])
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList());
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _openUrl(String url) async {
    await confirmOpenBrowser(context, url);
  }

  void _openProfile(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(onRetry: _load);
    }
    if (!_enabled) {
      return _EmptySponsor(title: _title, content: _content);
    }
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w =
            constraints.maxWidth > 720 ? 720 : constraints.maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _HeaderCard(title: _title, content: _content),
                if (_url.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openUrl(_url),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    icon: const Icon(Icons.favorite),
                    label: const Text('前往赞助'),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Icon(Icons.volunteer_activism, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '感谢以下赞助者',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '正是他们让这个小岛得以持续运转，我们由衷感谢每一位支持者。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_sponsors.isEmpty)
                  _noSponsor(scheme)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sponsors
                        .map((s) => _SponsorChip(
                              sponsor: s,
                              onTap: () =>
                                  _openProfile((s['username'] ?? '').toString()),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _noSponsor(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.favorite_border, size: 32, color: scheme.outline),
          const SizedBox(height: 8),
          Text(
            '还没有赞助者，成为第一个支持者吧',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 页头：柔和渐变卡 + 标题 + 富文本说明。
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.favorite, color: scheme.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.isEmpty ? '支持 DNAISLAND' : title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (content.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Html(
              data: content,
              onLinkTap: (href, _, _) {
                if (href != null && href.isNotEmpty) {
                  confirmOpenBrowser(context, href);
                }
              },
              extensions: <HtmlExtension>[TableHtmlExtension()],
              style: {
                'body': Style(
                  margin: Margins.zero,
                  fontSize: FontSize(14.5),
                  lineHeight: const LineHeight(1.65),
                  color: scheme.onSurface,
                ),
                'p': Style(margin: Margins.only(bottom: 8)),
                'a': Style(color: scheme.primary),
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 赞助者条目：头像 + 显示名 + 累计数额，点击进入其主页。
class _SponsorChip extends StatelessWidget {
  const _SponsorChip({required this.sponsor, required this.onTap});

  final Map<String, dynamic> sponsor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = (sponsor['display_name'] ?? '').toString();
    final amount = (sponsor['amount'] ?? '').toString();
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.favorite, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              if (amount.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 未启用赞助时的简洁占位页。
class _EmptySponsor extends StatelessWidget {
  const _EmptySponsor({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.volunteer_activism, size: 56, color: scheme.outline),
              const SizedBox(height: 12),
              Text(
                title.isEmpty ? '赞助' : title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                content.trim().isEmpty ? '赞助功能暂未开放，敬请期待。' : content,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
