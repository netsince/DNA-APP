import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/version_utils.dart';

/// 一次「应用内更新」的清单信息。
///
/// 清单由发布方上传到 `更新地址/update.json`，两种平台共用一个文件：
/// ```json
/// {
///   "android": {"versionCode": 2101, "versionName": "1.0.1",
///               "url": "https://.../DNA-ULTRA-1.0.1-arm64.apk",
///               "notes": "更新说明"},
///   "windows": {"version": "1.0.1",
///               "url": "https://.../DNA-ULTRA-1.0.1-win.zip",
///               "notes": "更新说明"}
/// }
/// ```
class AppUpdateManifest {
  const AppUpdateManifest({
    required this.version,
    required this.url,
    this.versionCode,
    this.notes = '',
  });

  final String version;
  final String url;
  final int? versionCode;
  final String notes;
}

/// 应用内更新：检查清单 → 下载安装包 → 触发安装。
///
/// - 安卓：下载 APK 后通过 MethodChannel 让系统弹「安装」；
/// - 桌面：下载整合包 → 解压 → 让一个 .cmd 等进程退出后覆盖文件并重启。
///
/// 更新地址默认为官方站点，可在「关于 → 应用内更新」里改成任意静态地址。
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  /// 默认更新清单所在目录（末尾不带斜杠）。
  static const String kDefaultBase = 'https://dnaopensource.netsince.com';

  static const String _kBaseKey = 'update_base_url';
  static const MethodChannel _channel =
      MethodChannel('com.netsince.dna/updater');

  /// 读取自定义更新地址（空 = 用默认）。
  Future<String> baseUrl() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String saved = (prefs.getString(_kBaseKey) ?? '').trim();
      return saved.isEmpty ? kDefaultBase : saved.replaceAll(RegExp(r'/+$'), '');
    } catch (_) {
      return kDefaultBase;
    }
  }

  Future<void> setBaseUrl(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String v = value.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_kBaseKey, v);
  }

  /// 当前安装版本（android 用 buildNumber 当 versionCode）。
  Future<String> currentVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return info.version.trim().isEmpty ? info.buildNumber.trim() : info.version.trim();
    } catch (_) {
      return '';
    }
  }

  Future<int> currentVersionCode() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 拉取清单；失败返回 null。
  Future<AppUpdateManifest?> fetch({String? base}) async {
    final String root = (base ?? await baseUrl()).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$root/update.json');
    try {
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final Object? node = Platform.isAndroid
          ? decoded['android']
          : (Platform.isWindows ? decoded['windows'] : null);
      if (node is! Map<String, dynamic>) return null;
      final String url = '${node['url'] ?? ''}'.trim();
      if (url.isEmpty) return null;
      final String version = Platform.isAndroid
          ? '${node['versionName'] ?? node['version'] ?? ''}'.trim()
          : '${node['version'] ?? node['versionName'] ?? ''}'.trim();
      return AppUpdateManifest(
        version: version,
        url: url,
        versionCode: (node['versionCode'] as num?)?.toInt(),
        notes: '${node['notes'] ?? ''}'.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 静默检查：有更新时返回清单（不做任何 UI），失败或无需更新返回 null。
  Future<AppUpdateManifest?> checkSilently() async {
    try {
      final AppUpdateManifest? manifest = await fetch();
      if (manifest == null) return null;
      if (!await isNewer(manifest)) return null;
      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// 清单里的版本是否比本机新。
  Future<bool> isNewer(AppUpdateManifest manifest) async {
    if (Platform.isAndroid && manifest.versionCode != null) {
      return manifest.versionCode! > await currentVersionCode();
    }
    final String local = await currentVersion();
    if (local.isEmpty || manifest.version.isEmpty) return false;
    if (!parseVersion(local).isValid || !parseVersion(manifest.version).isValid) {
      return false;
    }
    return isRemoteNewer(local, manifest.version);
  }

  /// 下载到临时目录，返回文件路径；[onProgress] 为 0–1。
  Future<String> download(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String name = url.split('/').last.split('?').first;
    final String safeName = name.isEmpty
        ? 'dna-update-${DateTime.now().millisecondsSinceEpoch}.bin'
        : name;
    final File out = File(
      '${dir.path}${Platform.pathSeparator}$safeName',
    );
    final http.Request req = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse res = await req.send().timeout(
          const Duration(minutes: 10),
        );
    if (res.statusCode != 200) {
      throw AppUpdateException('下载失败：HTTP ${res.statusCode}');
    }
    final int total = res.contentLength ?? 0;
    int received = 0;
    final IOSink sink = out.openWrite();
    try {
      await for (final List<int> chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return out.path;
  }

  /// 安卓：交给系统安装器。用户仍需在系统弹窗里点「安装」。
  Future<void> installAndroid(String apkPath) async {
    final bool ok = await _channel
            .invokeMethod<bool>('installApk', <String, String>{'path': apkPath}) ??
        false;
    if (!ok) throw const AppUpdateException('无法唤起系统安装器');
  }

  /// 桌面：解压整合包，写一个替换脚本，退出本进程后覆盖并重启。
  Future<void> applyWindows(String zipPath) async {
    final Directory temp = await getTemporaryDirectory();
    final String work = '${temp.path}${Platform.pathSeparator}dna_update';
    final Directory workDir = Directory(work);
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);
    final String extractDir = '$work\\extract';

    final ProcessResult unzip = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "$extractDir" -Force',
      ],
    );
    if (unzip.exitCode != 0) {
      throw AppUpdateException('解压失败：${unzip.stderr}');
    }

    // 包根目录可能直接是程序目录，也可能套了一层（如「电脑版」）。
    String src = extractDir;
    final Directory extract = Directory(extractDir);
    if (!File('$extractDir\\dna.exe').existsSync()) {
      for (final Directory sub in extract.listSync().whereType<Directory>()) {
        if (File('${sub.path}\\dna.exe').existsSync()) {
          src = sub.path;
          break;
        }
        for (final Directory d2 in sub.listSync().whereType<Directory>()) {
          if (File('${d2.path}\\dna.exe').existsSync()) {
            src = d2.path;
            break;
          }
        }
      }
    }
    if (!File('$src\\dna.exe').existsSync()) {
      throw const AppUpdateException('更新包结构不对：解压后没找到 dna.exe');
    }

    final String exeDir = File(Platform.resolvedExecutable).parent.path;
    String q(String v) => "'${v.replaceAll("'", "''")}'";
    final File script = File('$work\\apply_update.ps1');
    await script.writeAsString(
      <String>[
        r'$ErrorActionPreference = "SilentlyContinue"',
        '\$src = ${q(src)}',
        '\$dst = ${q(exeDir)}',
        'Start-Sleep -Seconds 3',
        'while (Get-Process dna -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 1 }',
        'robocopy \$src \$dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null',
        'Start-Process "\$dst\\dna.exe"',
        'Remove-Item \$PSCommandPath -Force',
      ].join('\r\n'),
      encoding: const Utf8Codec(),
    );
    // 带 BOM 写，PowerShell 5.1 才按 UTF-8 解析中文路径。
    final List<int> bytes = await script.readAsBytes();
    if (bytes.length < 3 || bytes[0] != 0xEF) {
      await script.writeAsBytes(
        <int>[0xEF, 0xBB, 0xBF, ...bytes],
        flush: true,
      );
    }
    await Process.start(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}

/// 应用内更新过程中的可读错误。
class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}
