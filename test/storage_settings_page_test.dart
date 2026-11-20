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
      '会话类',
      '角色卡类',
      '世界类',
      '缓存类',
      '下载类',
      '附件类',
      '其他类',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label 没显示');
    }
  });

  testWidgets('点分类进明细页，能看到条目', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report()));
    await tester.tap(find.text('会话类').first);
    await tester.pumpAndSettle();
    expect(find.text('和她的第一个夜晚'), findsWidgets);
    expect(find.textContaining('128 条消息'), findsWidgets);
  });

  testWidgets('占用条：每个非零分类一段、总宽铺满、颜色按分类顺序', (WidgetTester tester) async {
    await pump(tester, _FakeUsage(_report()));
    final ThemeData theme =
        Theme.of(tester.element(find.byType(StorageSettingsPage)));
    final ColorScheme cs = theme.colorScheme;
    final Finder bar = find.byKey(const ValueKey<String>('storage_usage_bar'));
    expect(bar, findsOneWidget);

    const List<StorageCategory> drawn = <StorageCategory>[
      StorageCategory.conversations,
      StorageCategory.characters,
      StorageCategory.worlds,
      StorageCategory.downloads,
      StorageCategory.attachments,
    ];
    double sumWidth = 0;
    for (final StorageCategory category in drawn) {
      final Finder seg =
          find.byKey(ValueKey<String>('storage_usage_seg_${category.name}'));
      expect(seg, findsOneWidget, reason: '${category.name} 没画出色段');
      final Size size = tester.getSize(seg);
      expect(size.width > 0, isTrue,
          reason: '${category.name} 的色段宽度是 ${size.width}，等于没画');
      expect(size.height > 0, isTrue);
      sumWidth += size.width;
      final double t =
          category.index / (StorageCategory.values.length - 1) * 0.85;
      final Color expected = Color.lerp(cs.primary, cs.tertiary, t) ?? cs.primary;
      expect(tester.widget<ColoredBox>(seg).color, expected);
    }
    // 零字节的分类不该有段。
    expect(
      find.byKey(const ValueKey<String>('storage_usage_seg_cache')),
      findsNothing,
    );
    // 占比极小时走构成模式：各段加起来应当接近整条宽度。
    final Size barSize = tester.getSize(bar);
    expect(barSize.width > 0, isTrue);
    expect(sumWidth > barSize.width * 0.95, isTrue,
        reason: '段总宽 ${sumWidth.toStringAsFixed(1)} 明显小于整条 ${barSize.width}');
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
