import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:flutter/material.dart';

/// 站点公开配置（来自 GET /api/v1/site-config），启动后加载一次并缓存。
class SiteConfig extends ChangeNotifier {
  SiteConfig._();
  static final SiteConfig instance = SiteConfig._();

  bool _loaded = false;
  bool get loaded => _loaded;

  String siteName = 'DNAISLAND';

  bool shutdownEnabled = false;
  String shutdownMessage = '';

  bool announcementEnabled = false;
  String announcementContent = '';

  bool heroEnabled = false;
  String heroTitle = '';
  String heroSubtitle = '';
  List<Map<String, String>> heroButtons = const [];

  String privacyPolicyUrl = '';
  String tosUrl = '';
  String contactEmail = '';

  /// 获取兑换码的跳转地址（可选）：配置后在积分页显示「获取积分」入口。
  String redeemCodeUrl = '';

  // 赞助页面配置（来自 site-config 的 sponsor 对象）。
  bool sponsorEnabled = false;
  String sponsorTitle = '';
  String sponsorContent = '';
  String sponsorUrl = '';

  /// 拉取站点配置。任何失败都回退到默认值并标记为已加载，避免阻断启动。
  Future<void> load() async {
    try {
      await ServerConfig.getBaseUrl(); // 确保缓存
      final data = await ApiClient.instance.getSiteConfig();
      siteName = data['site_name'] as String? ?? 'DNAISLAND';

      final shutdown = data['shutdown'] as Map<String, dynamic>? ?? {};
      shutdownEnabled = shutdown['enabled'] as bool? ?? false;
      shutdownMessage = shutdown['message'] as String? ?? '';

      final ann = data['announcement'] as Map<String, dynamic>? ?? {};
      announcementEnabled = ann['enabled'] as bool? ?? false;
      announcementContent = ann['content'] as String? ?? '';

      final hero = data['hero'] as Map<String, dynamic>? ?? {};
      heroEnabled = hero['enabled'] as bool? ?? false;
      heroTitle = hero['title'] as String? ?? '';
      heroSubtitle = hero['subtitle'] as String? ?? '';
      heroButtons = (hero['buttons'] as List? ?? [])
          .whereType<Map>()
          .map((b) => {
                'label': (b['label'] ?? '').toString(),
                'url': (b['url'] ?? '').toString(),
              })
          .toList();

      final agr = data['agreements'] as Map<String, dynamic>? ?? {};
      privacyPolicyUrl = agr['privacy_policy_url'] as String? ?? '';
      tosUrl = agr['tos_url'] as String? ?? '';

      contactEmail = data['contact_email'] as String? ?? '';
      redeemCodeUrl = data['redeem_code_url'] as String? ?? '';

      final sponsor = data['sponsor'] as Map<String, dynamic>? ?? {};
      sponsorEnabled = sponsor['enabled'] as bool? ?? false;
      sponsorTitle = sponsor['title'] as String? ?? '';
      sponsorContent = sponsor['content'] as String? ?? '';
      sponsorUrl = sponsor['url'] as String? ?? '';
    } catch (_) {
      // 未配置服务器或网络异常：保留默认配置，不阻断启动。
    }
    _loaded = true;
    notifyListeners();
  }
}
