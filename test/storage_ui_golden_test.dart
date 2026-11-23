import 'dart:io';

import 'package:dna/pages/settings/storage_settings_page.dart';
import 'package:dna/services/storage_usage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUsage extends StorageUsageService {
  @override
  Future<StorageUsageReport> scan() async => _report();
}

StorageUsageReport _report() {
  StorageCategoryUsage cat(StorageCategory c, int bytes,
          List<StorageUsageItem> items) =>
      StorageCategoryUsage(
        category: c,
        bytes: bytes,
        items: items,
        itemCount: items.length,
      );
  return StorageUsageReport(
    categories: <StorageCategoryUsage>[
      cat(StorageCategory.conversations, 4218880, <StorageUsageItem>[
        const StorageUsageItem(name: '和她的第一个夜晚', bytes: 2097152, note: '128 条消息'),
        const StorageUsageItem(name: '雨夜的便利店', bytes: 1572864, note: '96 条消息'),
        const StorageUsageItem(name: '周末群聊', bytes: 548864, note: '44 条消息'),
      ]),
      cat(StorageCategory.characters, 12582912, <StorageUsageItem>[
        const StorageUsageItem(name: '林夏', bytes: 6291456, note: '图片 3 张 · 音乐 1 首'),
        const StorageUsageItem(name: '周雨', bytes: 4194304, note: '图片 2 张'),
      ]),
      cat(StorageCategory.worlds, 1048576, <StorageUsageItem>[
        const StorageUsageItem(name: '雾港', bytes: 1048576, note: '12 个词条'),
      ]),
      cat(StorageCategory.cache, 3355443, const <StorageUsageItem>[
        StorageUsageItem(name: '图片缓存', bytes: 3355443),
      ]),
      cat(StorageCategory.downloads, 78643200, <StorageUsageItem>[
        const StorageUsageItem(name: 'tts_models/gpt_emb_quant_int8.onnx', bytes: 52428800),
        const StorageUsageItem(name: 'tts_models/vocos_spectrum.onnx', bytes: 26214400),
      ]),
      cat(StorageCategory.attachments, 6291456, <StorageUsageItem>[
        const StorageUsageItem(name: '设定文档.md', bytes: 4194304),
        const StorageUsageItem(name: '角色表.csv', bytes: 2097152),
      ]),
      cat(StorageCategory.other, 204800, const <StorageUsageItem>[
        StorageUsageItem(name: '导出临时文件', bytes: 204800),
      ]),
    ],
    totalBytes: 4218880 + 12582912 + 1048576 + 3355443 + 78643200 + 6291456 + 204800,
    scannedAt: DateTime(2026, 11, 21, 1, 30),
    disk: const StorageDiskSpace(
      totalBytes: 512 * 1024 * 1024 * 1024,
      freeBytes: 180 * 1024 * 1024 * 1024,
      label: 'C:',
    ),
  );
}

Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('SourceHanSans');
  for (final String path in <String>[
    'assets/fonts/SourceHanSansSC-Regular.otf',
    'assets/fonts/SourceHanSansSC-Medium.otf',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future<ByteData>.value(
        ByteData.view(file.readAsBytesSync().buffer),
      ));
    }
  }
  await loader.load();
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final File iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      final FontLoader icons = FontLoader('MaterialIcons');
      icons.addFont(Future<ByteData>.value(
        ByteData.view(iconFont.readAsBytesSync().buffer),
      ));
      await icons.load();
    }
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('存储空间：总览 + 七类', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'SourceHanSans',
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: StorageSettingsPage(service: _FakeUsage()),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/storage_overview.png'),
    );
  });

  testWidgets('存储空间：桌面宽窗口（内容列收窄）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1501, 859);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'SourceHanSans',
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: StorageSettingsPage(service: _FakeUsage()),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/storage_overview_wide.png'),
    );
  });

  testWidgets('存储空间：某个分类的明细页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'SourceHanSans',
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: StorageSettingsPage(service: _FakeUsage()),
    ));
    await tester.pumpAndSettle();
    // 点整行（ListTile），点 Text 会因为有 FitText 包裹而命中不到。
    await tester.tap(find.ancestor(
      of: find.text('角色卡').first,
      matching: find.byType(InkWell),
    ).first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/storage_detail.png'),
    );
  });
}
