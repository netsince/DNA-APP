// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/widgets/fit_text.dart';
import 'authors_page.dart';
import 'license_page.dart' as dna_license;
import 'open_source_page.dart';

/// 应用信息：名称、版本、作者、官网等。
abstract final class AppInfo {
  static const String name = '与汝共奏';
  static const String nameEn = 'Duet Nurturing Ally';
  static const String tagline = '开源 · 数据本地 · 隐私优先的角色扮演 APP';
  static const String officialSite = 'https://dnaopensource.netsince.com';
  static const String downloadPage = 'https://dnaopensource.netsince.com/download';
  static const String community = 'https://dnaisland.nb6.ltd';
  static const String sourceRepo = 'https://github.com/netsince/dna-app';
  static const String communityRepo = 'https://github.com/netsince/dnaisland';
  static const String supportEmail = 'supportdna@netsince.com';
  static const String supportEmail2 = 'support@netsince.com';
}

/// 关于页面：展示软件名称、版本、作者、官网、社区、许可证等信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final String v = info.version.trim();
      final String b = info.buildNumber.trim();
      setState(() {
        _version = v.isEmpty
            ? b
            : (b.isEmpty || b == v ? v : '$v+$b');
      });
    } catch (_) {}
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('无法打开链接：$url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('关于与开源')),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                children: <Widget>[
                  // ===== 1. 应用 Logo 与版本 =====
                  Center(
                    child: Column(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 88,
                            height: 88,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.auto_awesome,
                              size: 88,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FitText(
                          AppInfo.name,
                          style: ts.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        FitText(
                          AppInfo.nameEn,
                          style: ts.bodyMedium?.copyWith(color: cs.outline),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: FitText(
                            _version.isEmpty ? '版本加载中…' : 'v$_version',
                            style: ts.labelMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FitText(
                          AppInfo.tagline,
                          textAlign: TextAlign.center,
                          style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ===== 2. 项目成员 =====
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.people_outline, color: cs.onPrimaryContainer, size: 20),
                      ),
                      title: const FitText('项目参与人员名册'),
                      subtitle: const FitText('查看设计、研发与维护人员分工及个人网站'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const AuthorsPage()),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===== 3. 官方站点与社区 =====
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FitText('官方支持与社区', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _LinkRow(
                            icon: Icons.language,
                            title: '官方网站',
                            subtitle: AppInfo.officialSite,
                            onTap: () => _open(context, AppInfo.officialSite),
                          ),
                          const Divider(height: 1),
                          _LinkRow(
                            icon: Icons.forum_outlined,
                            title: 'DNA 社区',
                            subtitle: AppInfo.community,
                            onTap: () => _open(context, AppInfo.community),
                          ),
                          const Divider(height: 1),
                          _LinkRow(
                            icon: Icons.code,
                            title: 'GitHub 源代码仓库',
                            subtitle: AppInfo.sourceRepo,
                            onTap: () => _open(context, AppInfo.sourceRepo),
                          ),
                          const Divider(height: 1),
                          _LinkRow(
                            icon: Icons.email_outlined,
                            title: '反馈支持邮箱',
                            subtitle: AppInfo.supportEmail,
                            onTap: () => _open(context, 'mailto:${AppInfo.supportEmail}'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===== 4. 开源与许可证 =====
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FitText('开源与许可证', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          FitText(
                            '源代码采用 netSince 项目公开许可证 (nSPPL)，美术与标志资源采用 CC BY-NC-ND 4.0。',
                            style: ts.bodySmall?.copyWith(color: cs.outline),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(builder: (_) => const dna_license.LicensePage()),
                                  ),
                                  icon: const Icon(Icons.description_outlined, size: 18),
                                  label: const FitText('许可证全文'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(builder: (_) => const OpenSourcePage()),
                                  ),
                                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                                  label: const FitText('第三方组件'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: cs.primary, size: 20),
      title: FitText(title, style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: FitText(subtitle, style: ts.bodySmall?.copyWith(color: cs.primary)),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onTap,
    );
  }
}
