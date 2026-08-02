import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/widgets/fit_text.dart';
import 'authors_page.dart';
import 'license_page.dart' as dna_license;
import 'open_source_page.dart';

/// 应用信息：名称、版本、作者、官网等。
///
/// 版本号不在此硬编码，运行时通过 `package_info_plus` 从各平台读取，
/// 与 `pubspec.yaml` 的 `version` 自动保持一致，升级时无需额外修改。
abstract final class AppInfo {
  static const String name = '与汝共奏';
  static const String nameEn = 'Duet Nurturing Ally';
  static const String tagline = '开源 · 数据本地 · 隐私优先的角色扮演 APP';
  static const String officialSite = 'https://dnaopensource.netsince.com';
  static const String downloadPage = 'https://dnaopensource.netsince.com/download';
  static const String community = 'https://dnaisland.nb6.ltd';
  static const String sourceRepo = 'https://github.com/netsince/dna-app';
  static const String communityRepo = 'https://github.com/netsince/dnaisland';
}

/// 关于页面：展示软件名称、版本、作者、官网、社区、许可证等信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 运行时读取的应用版本字符串，如 `0.2.0+13`。加载失败时回退为空。
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
    } catch (_) {
      // 无法读取版本号时保持为空。
    }
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('关于')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                children: <Widget>[
                  // ---- 应用图标 + 名称 ----
                  Center(
                    child: Column(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 96,
                            height: 96,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.auto_awesome,
                              size: 96,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FitText(
                          AppInfo.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        FitText(
                          AppInfo.nameEn,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: FitText(
                            _version.isEmpty ? '版本信息加载中…' : '版本 $_version',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: cs.onPrimaryContainer),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FitText(
                          AppInfo.tagline,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 8),

                  // ---- 参与人员 ----
                  _sectionTitle(context, '参与人员'),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: const FitText('参与人员名单'),
                    subtitle: const FitText('查看各参与人员的名称、分工、别名与个人网站'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AuthorsPage()),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ---- 相关链接 ----
                  _sectionTitle(context, '相关链接'),
                  const SizedBox(height: 4),
                  _LinkTile(
                    icon: Icons.language,
                    title: '官方网站',
                    subtitle: AppInfo.officialSite,
                    onTap: () => _open(context, AppInfo.officialSite),
                  ),
                  _LinkTile(
                    icon: Icons.download_outlined,
                    title: '下载页面',
                    subtitle: AppInfo.downloadPage,
                    onTap: () => _open(context, AppInfo.downloadPage),
                  ),
                  _LinkTile(
                    icon: Icons.forum_outlined,
                    title: '社区',
                    subtitle: AppInfo.community,
                    onTap: () => _open(context, AppInfo.community),
                  ),
                  _LinkTile(
                    icon: Icons.code,
                    title: '源代码仓库',
                    subtitle: AppInfo.sourceRepo,
                    onTap: () => _open(context, AppInfo.sourceRepo),
                  ),
                  _LinkTile(
                    icon: Icons.extension_outlined,
                    title: '社区开源仓库',
                    subtitle: AppInfo.communityRepo,
                    onTap: () => _open(context, AppInfo.communityRepo),
                  ),
                  const SizedBox(height: 8),

                  // ---- 开源与许可证 ----
                  _sectionTitle(context, '开源与许可证'),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const FitText('本项目许可证'),
                    subtitle: const FitText(
                      '源代码采用 netSince.com 项目公开许可证 (nSPPL)，'
                      '美术资源（如 LOGO）采用 CC BY-NC-ND 4.0。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const dna_license.LicensePage()),
                        ),
                        icon: const Icon(Icons.description_outlined),
                        label: const FitText('本项目许可证全文'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const OpenSourcePage()),
                        ),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const FitText('第三方开源组件'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return FitText(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: FitText(title),
      subtitle: FitText(subtitle, style: TextStyle(color: cs.primary)),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}
