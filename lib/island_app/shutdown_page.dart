import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/site_config.dart';

/// 关站页：站点维护中说明 + 公告，点击“好的”返回首页。
class ShutdownPage extends StatelessWidget {
  final VoidCallback? onDismissed;
  const ShutdownPage({super.key, this.onDismissed});

  @override
  Widget build(BuildContext context) {
    final cfg = SiteConfig.instance;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 56, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                '站点维护中',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              if (cfg.shutdownMessage.isNotEmpty)
                Text(cfg.shutdownMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (cfg.announcementEnabled && cfg.announcementContent.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('公告',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Html(
                          data: cfg.announcementContent,
                          extensions: <HtmlExtension>[TableHtmlExtension()],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  onDismissed?.call();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RootShell()),
                  );
                },
                child: const Text('好的'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
