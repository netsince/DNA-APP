import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/utils/external_link.dart';

/// 关于（协议链接 + 联系邮箱 + 版本号），无脚手架，由 [RootShell] 承载。
class AboutBody extends StatefulWidget {
  const AboutBody({super.key});

  @override
  State<AboutBody> createState() => _AboutBodyState();
}

class _AboutBodyState extends State<AboutBody> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    await confirmOpenBrowser(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = SiteConfig.instance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.new_releases),
          title: const Text('版本'),
          subtitle: Text(_version.isEmpty ? '…' : _version),
        ),
        if (cfg.privacyPolicyUrl.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.policy),
            title: const Text('隐私政策'),
            onTap: () => _open(cfg.privacyPolicyUrl),
          ),
        if (cfg.tosUrl.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('用户协议'),
            onTap: () => _open(cfg.tosUrl),
          ),
        if (cfg.contactEmail.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.email),
            title: const Text('联系我们'),
            subtitle: Text(cfg.contactEmail),
            onTap: () => _open('mailto:${cfg.contactEmail}'),
          ),
      ],
    );
  }
}
