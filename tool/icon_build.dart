// 图标一键生成脚本：单一图标源（assets/icons + tool/icons_config.json）
// 生成 Android mipmap + Windows ico，并自动更新 Dart 枚举 / AndroidManifest / resource.h / Runner.rc。
//
// 用法：
//   dart run tool/icon_build.dart
//
// 加图标步骤：把源 PNG 放到 assets/icons/，在 tool/icons_config.json 里加一条记录，运行本脚本即可。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图标清单。
class IconSpec {
  IconSpec(this.map);
  final Map<String, dynamic> map;

  String get key => map['key'] as String;
  String get enumName => map['enumName'] as String;
  String get label => map['label'] as String;
  String get alias => map['alias'] as String;
  String get source => map['source'] as String;
  String get resourceId => map['resourceId'] as String;
  String get androidIconName => map['androidIconName'] as String;
  String get winIcoName => map['winIcoName'] as String;
  int get id => map['id'] as int;
}

void main(List<String> args) {
  final root = Directory.current.path;
  final config = jsonDecode(File('${root}/tool/icons_config.json').readAsStringSync())
      as Map<String, dynamic>;

  final mipmapDir = config['androidMipmapDir'] as String;
  final winResDir = config['windowsResourceDir'] as String;
  final winHeader = config['windowsResourceHeader'] as String;
  final winRc = config['windowsResourceScript'] as String;
  final dartEnumFile = config['dartEnumFile'] as String;
  final androidManifest = config['androidManifest'] as String;
  final targetActivity = config['androidTargetActivity'] as String;

  // 赋予 id：顺序即 id（101 起始）。
  final rawIcons = (config['icons'] as List)
      .cast<Map<String, dynamic>>()
      .asMap()
      .entries
      .map((e) {
        final m = Map<String, dynamic>.from(e.value);
        m['id'] = 101 + e.key;
        return IconSpec(m);
      })
      .toList();

  print('共 ${rawIcons.length} 个图标，开始生成...');

  // 1) 生成 Android mipmap
  final androidSizes = <String, int>{
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final spec in rawIcons) {
    final srcImg = img.decodeImage(File('${root}/${spec.source}').readAsBytesSync())!;
    for (final entry in androidSizes.entries) {
      final size = entry.value;
      final resized = img.copyResize(srcImg, width: size, height: size,
          interpolation: img.Interpolation.average);
      final dir = '${root}/$mipmapDir/${entry.key}';
      Directory(dir).createSync(recursive: true);
      final outPath = '$dir/${spec.androidIconName}.png';
      File(outPath).writeAsBytesSync(img.encodePng(resized));
    }
    print('  [Android] ${spec.androidIconName} -> mipmap 完成');
  }

  // 2) 生成 Windows 多尺寸 ico
  const winSizes = <int>[16, 24, 32, 48, 64, 128, 256];
  Directory('${root}/$winResDir').createSync(recursive: true);
  for (final spec in rawIcons) {
    final srcImg = img.decodeImage(File('${root}/${spec.source}').readAsBytesSync())!;
    final pngFrames = <Uint8List>[];
    for (final size in winSizes) {
      final resized = img.copyResize(srcImg, width: size, height: size,
          interpolation: img.Interpolation.average);
      pngFrames.add(Uint8List.fromList(img.encodePng(resized)));
    }
    final icoBytes = _encodeIco(pngFrames, winSizes);
    final icoName = spec.winIcoName;
    File('${root}/$winResDir/$icoName.ico')
        .writeAsBytesSync(icoBytes);
    print('  [Windows] $icoName.ico 完成');
  }

  // 3) 重写 Dart 枚举
  _writeDartEnum('${root}/$dartEnumFile', rawIcons);

  // 4) 重写 AndroidManifest activity-alias 区
  _writeAndroidManifest('${root}/$androidManifest', rawIcons, targetActivity);

  // 5) 重写 resource.h 与 Runner.rc
  _writeWindowsResources('${root}/$winHeader', '${root}/$winRc', rawIcons);

  print('完成。');
}

/// 构造多尺寸 ICO（PNG 帧）。
Uint8List _encodeIco(List<Uint8List> pngFrames, List<int> sizes) {
  final out = BytesBuilder();
  final count = pngFrames.length;
  // ICONDIR
  _writeU16(out, 0);
  _writeU16(out, 1); // type = icon
  _writeU16(out, count);

  // ICONDIRENTRY
  final entries = <int, (int, int)>{};
  var offset = 6 + 16 * count;
  for (var i = 0; i < count; i++) {
    final bytes = pngFrames[i];
    entries[i] = (bytes.length, offset);
    offset += bytes.length;
  }
  for (var i = 0; i < count; i++) {
    final (len, off) = entries[i]!;
    final size = sizes[i];
    final sizeByte = size >= 256 ? 0 : size;
    out.addByte(sizeByte);
    out.addByte(sizeByte);
    out.addByte(0);
    out.addByte(0);
    _writeU16(out, 1); // planes
    _writeU16(out, 32); // bitcount
    _writeU32(out, len);
    _writeU32(out, off);
  }
  for (var i = 0; i < count; i++) {
    out.add(pngFrames[i]);
  }
  return out.toBytes();
}

void _writeU16(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
}

void _writeU32(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}

/// 重写 lib/services/app_icon_service.dart。
void _writeDartEnum(String path, List<IconSpec> specs) {
  final b = StringBuffer();
  b.writeln("import 'dart:io';");
  b.writeln();
  b.writeln("import 'package:flutter/foundation.dart';");
  b.writeln("import 'package:flutter/services.dart';");
  b.writeln();
  b.writeln('/// 应用图标切换服务。');
  b.writeln('///');
  b.writeln('/// 仅 Android 支持运行时切换启动图标（通过 activity-alias 启用/禁用实现）。');
  b.writeln('/// 其他平台（iOS / 桌面 / Web）操作系统不允许运行时更换图标，[isSupported] 为 false，');
  b.writeln('/// 调用 [setIcon] 会抛出 [UnsupportedError]。');
  b.writeln('///');
  b.writeln('/// 本文件由 tool/icon_build.dart 自动生成，请勿手动编辑。');
  b.writeln('class AppIconService {');
  b.writeln('  AppIconService._();');
  b.writeln();
  b.writeln("  static const MethodChannel _channel =");
  b.writeln("      MethodChannel('com.netsince.dna/app_icon');");
  b.writeln();
  b.writeln('  /// 当前平台是否支持运行时切换图标。');
  b.writeln('  static bool get isSupported => !kIsWeb && Platform.isAndroid;');
  b.writeln();
  b.writeln('  /// 可用的图标选项。');
  b.writeln('  static const List<AppIconOption> availableOptions = <AppIconOption>[');
  for (final spec in specs) {
    b.writeln('    AppIconOption.${spec.enumName},');
  }
  b.writeln('  ];');
  b.writeln();
  b.writeln('  /// 切换到指定图标。非 Android 平台会抛出 [UnsupportedError]。');
  b.writeln('  static Future<void> setIcon(AppIconOption option) async {');
  b.writeln('    if (!isSupported) {');
  b.writeln("      throw UnsupportedError('应用图标切换仅支持 Android 平台。');");
  b.writeln('    }');
  b.writeln('    await _channel.invokeMethod<void>(');
  b.writeln("      'setIcon',");
  b.writeln("      <String, String>{'name': option.alias},");
  b.writeln('    );');
  b.writeln('  }');
  b.writeln();
  b.writeln('  /// 根据 key 查找图标选项；未知 key 回退到默认图标。');
  b.writeln('  static AppIconOption optionForKey(String key) {');
  b.writeln('    for (final AppIconOption opt in availableOptions) {');
  b.writeln('      if (opt.key == key) return opt;');
  b.writeln('    }');
  b.writeln('    return AppIconOption.${specs.first.enumName};');
  b.writeln('  }');
  b.writeln('}');
  b.writeln();
  b.writeln('/// 应用图标选项。');
  b.writeln('enum AppIconOption {');
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i];
    final comma = i == specs.length - 1 ? ';' : ',';
    b.writeln("  ${s.enumName}('${s.key}', '${s.label}', '${s.source}', '${s.alias}')$comma");
  }
  b.writeln();
  b.writeln('  const AppIconOption(this.key, this.label, this.assetPath, this.alias);');
  b.writeln();
  b.writeln('  /// 持久化存储用的键。');
  b.writeln('  final String key;');
  b.writeln();
  b.writeln('  /// 设置页展示用的名称。');
  b.writeln('  final String label;');
  b.writeln();
  b.writeln('  /// 设置页预览用的资源路径。');
  b.writeln('  final String assetPath;');
  b.writeln();
  b.writeln('  /// Android activity-alias 名。');
  b.writeln('  final String alias;');
  b.writeln('}');
  b.writeln();
  File(path).writeAsStringSync(b.toString());
  print('  [Dart] 已重写 $path');
}

/// 重写 AndroidManifest.xml 中的 activity-alias 区（用 marker 包围）。
void _writeAndroidManifest(String path, List<IconSpec> specs, String targetActivity) {
  var content = File(path).readAsStringSync();
  final startMarker = '<!-- ICON_ALIASES_START -->';
  final endMarker = '<!-- ICON_ALIASES_END -->';

  final sb = StringBuffer();
  sb.writeln('        $startMarker');
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final resName = spec.androidIconName;
    // 第一个图标（默认）必须为 enabled="true"，否则首次安装无桌面图标。
    final enabled = i == 0 ? 'true' : 'false';
    sb.writeln('        <activity-alias');
    sb.writeln('            android:name=".${spec.alias}"');
    sb.writeln('            android:enabled="$enabled"');
    sb.writeln('            android:exported="true"');
    sb.writeln('            android:icon="@mipmap/$resName"');
    sb.writeln('            android:label="@string/app_name"');
    sb.writeln('            android:targetActivity="$targetActivity"');
    sb.writeln('            android:taskAffinity="">');
    sb.writeln('            <intent-filter>');
    sb.writeln('                <action android:name="android.intent.action.MAIN" />');
    sb.writeln('                <category android:name="android.intent.category.LAUNCHER" />');
    sb.writeln('            </intent-filter>');
    sb.writeln('        </activity-alias>');
  }
  sb.writeln('        $endMarker');

  // 若已有 marker，则替换区间；否则在 <application> 关闭前插入。
  if (content.contains(startMarker) && content.contains(endMarker)) {
    final start = content.indexOf(startMarker);
    final end = content.indexOf(endMarker) + endMarker.length;
    content = content.replaceRange(start, end, sb.toString());
  } else {
    // 找 </application> 之前的 activity 列表尾部插入。这里插到第一个 <activity-alias 之前不现实，
    // 简单起见插到 </application> 前。
    final insertAt = content.indexOf('</application>');
    if (insertAt < 0) {
      throw StateError('AndroidManifest 未找到 </application>');
    }
    content = content.replaceRange(insertAt, insertAt, sb.toString());
  }
  File(path).writeAsStringSync(content);
  print('  [AndroidManifest] 已更新 activity-alias 区');
}

/// 重写 resource.h 与 Runner.rc。
void _writeWindowsResources(String headerPath, String rcPath, List<IconSpec> specs) {
  // resource.h：整体重写。
  final hb = StringBuffer();
  hb.writeln('//{{NO_DEPENDENCIES}}');
  hb.writeln('// Microsoft Visual C++ generated include file.');
  hb.writeln('// Used by Runner.rc');
  hb.writeln('//');
  hb.writeln('// This file is auto-generated by tool/icon_build.dart. Do not edit.');
  hb.writeln('//');
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i];
    if (i == 0) {
      hb.writeln('#define ${s.resourceId}                    ${s.id}');
    } else {
      hb.writeln('#define ${s.resourceId}                ${s.id}');
    }
  }
  hb.writeln();
  hb.writeln('// Next default values for new objects');
  hb.writeln('//');
  hb.writeln('#ifdef APSTUDIO_INVOKED');
  hb.writeln('#ifndef APSTUDIO_READONLY_SYMBOLS');
  hb.writeln('#define _APS_NEXT_RESOURCE_VALUE        ${specs.length + 1 + 100}');
  hb.writeln('#define _APS_NEXT_COMMAND_VALUE         40001');
  hb.writeln('#define _APS_NEXT_CONTROL_VALUE         1001');
  hb.writeln('#define _APS_NEXT_SYMED_VALUE           101');
  hb.writeln('#endif');
  hb.writeln('#endif');
  hb.writeln();
  File(headerPath).writeAsStringSync(hb.toString());
  print('  [resource.h] 已重写');

  // Runner.rc：只重写 ICON 声明区（用 marker 包围）。
  var rc = File(rcPath).readAsStringSync();
  const startMarker = '// ICON_DECLS_START';
  const endMarker = '// ICON_DECLS_END';

  final rb = StringBuffer();
  rb.writeln('    $startMarker');
  for (final spec in specs) {
    rb.writeln('${spec.resourceId}   ICON   "resources\\\\${spec.winIcoName}.ico"');
  }
  rb.writeln('    $endMarker');

  if (rc.contains(startMarker) && rc.contains(endMarker)) {
    final start = rc.indexOf(startMarker);
    final end = rc.indexOf(endMarker) + endMarker.length;
    rc = rc.replaceRange(start, end, rb.toString());
  } else {
    // 首运行：在 IDI_APP_ICON 所在行之后插入 marker 区。
    final idx = rc.indexOf('IDI_APP_ICON');
    if (idx < 0) throw StateError('Runner.rc 未找到 IDI_APP_ICON');
    final lineEnd = rc.indexOf('\n', idx);
    rc = rc.replaceRange(lineEnd + 1, lineEnd + 1, '\n${rb.toString()}');
  }
  File(rcPath).writeAsStringSync(rc);
  print('  [Runner.rc] 已更新 ICON 区');
}
