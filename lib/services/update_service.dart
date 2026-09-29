import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/version_utils.dart';

/// 一次更新检查的结果。
class UpdateInfo {
  const UpdateInfo({
    required this.remoteVersion,
    required this.localVersion,
    required this.changelog,
    required this.publishedAt,
    required this.releaseUrl,
  });

  /// 远端版本号(已从 tag 解析出的规范形式,如 `0.3.0`)。
  final String remoteVersion;

  /// 本地版本号(如 `0.2.1`)。
  final String localVersion;

  /// release 正文(更新日志,Markdown 原文)。
  final String changelog;

  /// 发布时间。
  final DateTime? publishedAt;

  /// GitHub release 页面地址。
  final String releaseUrl;
}

/// 检查更新失败的原因。
enum UpdateCheckError {
  /// 网络不通 / 超时 / DNS 失败。
  network,

  /// 服务端返回非 200(404 = 仓库或 release 不存在,403 = 限流)。
  http,

  /// 返回内容不是预期 JSON,或缺少必需字段。
  malformed,

  /// **读不到本地版本号**(PackageInfo 不可用)。
  ///
  /// 与上面三种不同:这不是"网络不好",而是应用自身取不到版本。
  /// 启动检查时对这种情况**不提示**,否则用户每次启动都会看到
  /// 一条他自己无法解决的错误。
  localVersionUnavailable,
}

/// 检查更新的结果。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 有可用更新。
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

/// 已是最新版本。
class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate(this.localVersion, this.remoteVersion);
  final String localVersion;
  final String remoteVersion;
}

/// 检查失败。
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.error, this.detail);
  final UpdateCheckError error;
  final String detail;
}

/// 更新检测服务。
///
/// ## 只做检测,不做下载
///
/// **本服务刻意不实现任何自动下载 / 安装逻辑**:检测到新版本后只引导
/// 用户前往官网下载页,由用户自己决定。这既是产品要求,也避免了在
/// 应用内执行下载-替换二进制的风险。
class UpdateService {
  UpdateService({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// GitHub 仓库。
  static const String repoApi =
      'https://api.github.com/repos/netsince/DNA-APP/releases/latest';

  /// 检测到新版本后引导前往的下载页。
  static const String downloadPage =
      'https://dnaopensource.netsince.com/download/';

  /// 本地版本(不含 build 号,如 `0.2.1`)。
  ///
  /// `PackageInfo.version` 本身就不含 build 号,`buildNumber` 才带,
  /// 所以这里直接用 `version` —— 正好符合「比较时不算 +aaa」的要求。
  Future<String> localVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return info.version.trim();
    } catch (_) {
      return '';
    }
  }

  /// 查一次更新。
  ///
  /// [remoteOverride] 仅用于测试(`tryupdate` 命令与单元测试),
  /// 传入后不发起网络请求。
  Future<UpdateCheckResult> check({UpdateInfo? remoteOverride}) async {
    final String local = await localVersion();
    if (remoteOverride != null) {
      return _decide(local, remoteOverride);
    }

    late final http.Response resp;
    try {
      resp = await _client.get(
        Uri.parse(repoApi),
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DNA-APP-UpdateCheck',
        },
      ).timeout(timeout);
    } catch (e) {
      return UpdateCheckFailed(UpdateCheckError.network, e.toString());
    }

    if (resp.statusCode != 200) {
      return UpdateCheckFailed(
        UpdateCheckError.http,
        'HTTP ${resp.statusCode}',
      );
    }

    final UpdateInfo info;
    try {
      final Object? decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckFailed(
            UpdateCheckError.malformed, '响应不是 JSON 对象');
      }
      info = parseRelease(decoded);
    } catch (e) {
      return UpdateCheckFailed(UpdateCheckError.malformed, e.toString());
    }

    return _decide(local, info);
  }

  /// 从 GitHub release JSON 构造 [UpdateInfo]。
  ///
  /// 抽成静态方法便于单元测试直接喂 JSON,不需要起 HTTP。
  static UpdateInfo parseRelease(Map<String, dynamic> json) {
    // tag 优先;没有就退回 name;都没有则抛错由调用方归类为 malformed。
    final String tag = (json['tag_name'] as String?)?.trim().isNotEmpty == true
        ? (json['tag_name'] as String).trim()
        : ((json['name'] as String?) ?? '').trim();
    if (tag.isEmpty) {
      throw const FormatException('release 缺少 tag_name / name');
    }

    final ParsedVersion parsed = parseVersion(tag);
    if (!parsed.isValid) {
      throw FormatException('无法从 tag 解析版本号: $tag');
    }

    DateTime? published;
    final String? pubRaw = json['published_at'] as String?;
    if (pubRaw != null && pubRaw.isNotEmpty) {
      published = DateTime.tryParse(pubRaw)?.toLocal();
    }

    return UpdateInfo(
      remoteVersion: parsed.display,
      localVersion: '',
      changelog: (json['body'] as String?) ?? '',
      publishedAt: published,
      releaseUrl: (json['html_url'] as String?) ?? '',
    );
  }

  /// 比较本地与远端,决定结果。
  UpdateCheckResult _decide(String local, UpdateInfo info) {
    final String remote = info.remoteVersion;

    // 读不到本地版本 -> 单独归类,启动检查时静默(用户无法解决)。
    if (local.isEmpty || !parseVersion(local).isValid) {
      return UpdateCheckFailed(
        UpdateCheckError.localVersionUnavailable,
        'local="$local"',
      );
    }

    // 远端解析不了 -> 属于数据异常,可提示。
    if (!parseVersion(remote).isValid) {
      return UpdateCheckFailed(
        UpdateCheckError.malformed,
        'remote="$remote"',
      );
    }

    if (isRemoteNewer(local, remote)) {
      return UpdateAvailable(UpdateInfo(
        remoteVersion: remote,
        localVersion: local,
        changelog: info.changelog,
        publishedAt: info.publishedAt,
        releaseUrl: info.releaseUrl,
      ));
    }
    return UpdateUpToDate(local, remote);
  }
}

/// `tryupdate` 命令用的假更新:版本 999.999.999,日志「测试」。
///
/// 发布时间由调用方传入当前时间,保证每次都是"刚刚"。
UpdateInfo debugUpdateInfo(DateTime now) => UpdateInfo(
      remoteVersion: '999.999.999',
      localVersion: '',
      changelog: '测试',
      publishedAt: now,
      releaseUrl: UpdateService.downloadPage,
    );
