import 'package:dna/pages/settings/storage_settings_page.dart';
import 'package:dna/services/storage_usage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假盘点服务：直接返回构造好的报告，不碰真实磁盘/数据库。
class _FakeUsage extends StorageUsageService {
  _FakeUsage(this.report);

  final StorageUsageReport? report;

  @override
  Future<StorageUsageReport> scan() async {
    final StorageUsageReport? r = report;
    if (r == null) throw StateError('磁盘不可读');
    return r;
  }
}

StorageUsageReport _report({String? recordsError}) {
  StorageCategoryUsage cat(
    StorageCategory c,
    int bytes,
    List<StorageUsageItem> items,
  ) =>
      StorageCategoryUsage(
        category: c,
        bytes: bytes,
        items: items,
        itemCount: items.length,
      );
  final List<StorageCategoryUsage> cats = <StorageCategoryUsage>[
    cat(StorageCategory.conversations, 4096, <StorageUsageItem>[
      const StorageUsageItem(name: '和她的第一个夜晚', bytes: 4096, note: '128 条消息'),
    ]),
    cat(StorageCategory.characters, 2048, const <StorageUsageItem>[]),
    cat(StorageCategory.worlds, 1024, const <StorageUsageItem>[]),
    cat(StorageCategory.cache, 0, const <StorageUsageItem>[]),
    cat(StorageCategory.downloads, 8192, <StorageUsageItem>[
      const StorageUsageItem(name: 'tts 模型文件', bytes: 8192),
    ]),
    cat(StorageCategory.attachments, 512, <StorageUsageItem>[
      const StorageUsageItem(name: '设定文档.md', bytes: 512),
    ]),
    cat(StorageCategory.other, 0, const <StorageUsageItem>[]),
  ];
  return StorageUsageReport(
    categories: cats,
    totalBytes: 4096 + 2048 + 1024 + 8192 + 512,
    scannedAt: DateTime(2026, 11, 21),
    disk: const StorageDiskSpace(
      totalBytes: 100 * 1024 * 1024,
      freeBytes: 40 * 1024 * 1024,
      label: 'C:',
    ),
    recordsError: recordsError,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, StorageUsageService service) async {
    await tester.pumpWidget(
      MaterialApp(home: StorageSettingsPage(service: service)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('总览 + 七类明细都渲染出来', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report()));
    for (final String label in <String>[
      '会话',
      '角色卡',
      '世界',
      '缓存',
      '下载',
      '附件',
      '其他',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label 没显示');
    }
  });

  testWidgets('点分类进明细页，能看到条目', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report()));
    await tester.tap(find.text('会话').first);
    await tester.pumpAndSettle();
    expect(find.text('和她的第一个夜晚'), findsWidgets);
    expect(find.textContaining('128 条消息'), findsWidgets);
  });

  testWidgets('占用条：每类一段、七种不同色、段间留缝、宽度铺满', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report()));
    final ThemeData theme =
        Theme.of(tester.element(find.byType(StorageSettingsPage)));
    final Finder bar = find.byKey(const ValueKey<String>('storage_usage_bar'));
    final Size barSize = tester.getSize(bar);
    expect(barSize.height >= 16, isTrue, reason: '条形太细撑不起总览');

    const List<StorageCategory> drawn = <StorageCategory>[
      StorageCategory.conversations,
      StorageCategory.characters,
      StorageCategory.worlds,
      StorageCategory.downloads,
      StorageCategory.attachments,
    ];
    final List<Color> colors = <Color>[];
    double segWidth = 0;
    for (final StorageCategory category in drawn) {
      final Finder seg =
          find.byKey(ValueKey<String>('storage_usage_seg_${category.name}'));
      expect(seg, findsOneWidget, reason: '${category.name} 没画出色段');
      final Size size = tester.getSize(seg);
      expect(size.width > 0 && size.height > 0, isTrue,
          reason: '${category.name} 色段尺寸为 ${size.width}x${size.height}');
      segWidth += size.width;
      final Color actual = tester.widget<ColoredBox>(seg).color;
      expect(actual, storageCategoryColor(theme.colorScheme, category),
          reason: '${category.name} 的颜色与分类色不一致');
      colors.add(actual);
    }
    // 每一段必须是不同的颜色，而且离得够远（以前是同色相插值，肉眼分不出）。
    for (int i = 0; i < colors.length; i++) {
      for (int j = i + 1; j < colors.length; j++) {
        final int dr = ((colors[i].r - colors[j].r) * 255).abs().round();
        final int dg = ((colors[i].g - colors[j].g) * 255).abs().round();
        final int db = ((colors[i].b - colors[j].b) * 255).abs().round();
        final int dist = (dr * dr + dg * dg + db * db);
        expect(dist > 60 * 60, isTrue,
            reason: '第 $i 段和第 $j 段颜色太接近（RGB 距离平方 $dist）');
      }
    }
    // 零字节分类不画段。
    expect(find.byKey(const ValueKey<String>('storage_usage_seg_cache')),
        findsNothing);
    // 总量条被切成若干段 + 段间留缝，加起来应当接近整条宽度。
    expect(segWidth > barSize.width * 0.9, isTrue,
        reason: '段总宽 ${segWidth.toStringAsFixed(1)} 与整条 ${barSize.width} 差得太多');
  });

  testWidgets('扫描失败要说明原因并给重试', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(null));
    expect(find.textContaining('磁盘不可读'), findsWidgets);
    expect(find.textContaining('重试'), findsWidgets);
  });

  testWidgets('读库失败时明确提示，不静默给个偏小的数', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report(recordsError: 'Hive 启动失败')));
    expect(find.textContaining('Hive 启动失败'), findsWidgets);
  });
}
