import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dna/island_app/server_config.dart';

/// 在打开外部浏览器前弹出确认对话框（对齐网页版 `/teahouse/leave` 外链中转）。
///
/// - 解析并校验 URL（必须为 http/https）；
/// - 弹「即将离开 DNAISLAND」确认框，提示将跳转至浏览器；
/// - 用户确认后调用系统浏览器打开，返回 true；取消或无法打开返回 false。
Future<bool> confirmOpenBrowser(BuildContext context, String url) async {
  final resolved = ServerConfig.resolveUrl(url);
  final uri = Uri.tryParse(resolved);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('即将离开 DNAISLAND'),
      content: SingleChildScrollView(
        child: Text(
          '即将跳转至浏览器打开外部链接：\n$resolved\n\n'
          'DNAISLAND 无法保证外部网站的安全性或内容真实性，请自行判断并保护好个人信息。',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('继续访问'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }
  return false;
}
