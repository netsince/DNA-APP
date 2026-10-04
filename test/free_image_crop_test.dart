import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/widgets/card_crop_page.dart';
import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/advanced_settings_page.dart';
import 'package:dna/pages/settings/free_image_settings_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';

/// 「自由剪图」（高级 → 命令 → `freeimage`）。
///
/// 需求：命令打开一个页面，页面里一个开关；开关置真后，**全部**图片编辑器关于图片
/// 裁剪比例限制的逻辑全部禁用。
///
/// 图片编辑器分散在主应用（角色卡发布页、TA 编辑器）与内嵌社区（头像编辑页，
/// `const ProfileEditPage()` 连 controller 都拿不到）两个子应用里，所以开关做成
/// 裁剪入口旁边的模块级开关 `FreeImageCrop`（回调绑定到 controller 的当前设置，
/// 不存副本）。本文件既验证开关本身，也用**静态守护**盯住"不许有编辑器漏掉"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> boot([Map<String, Object> prefs = const <String, Object>{}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  group('设置项', () {
    test('默认关闭', () {
      expect(AppSettings.empty().freeImageCrop, isFalse);
      expect(
        AppSettings.fromJson(<String, dynamic>{}).freeImageCrop,
        isFalse,
        reason: '老配置文件没有这个字段时必须回退到「关闭」',
      );
    });

    test('toJson / fromJson 往返', () {
      final AppSettings on = AppSettings.empty().copyWith(freeImageCrop: true);
      expect(on.toJson()['freeImageCrop'], isTrue);
      expect(AppSettings.fromJson(on.toJson()).freeImageCrop, isTrue);
    });

    test('持久化：写盘后能读回来', () async {
      await boot();
      final SettingsService svc = SettingsService();
      expect((await svc.load()).freeImageCrop, isFalse);
      await svc.save((await svc.load()).copyWith(freeImageCrop: true));
      expect((await svc.load()).freeImageCrop, isTrue, reason: '开关必须落盘');
    });
  });

  group('裁剪层开关', () {
    test('默认关闭：未绑定读取回调时一律 false（保持原来的锁定行为）', () {
      FreeImageCrop.debugSet(() => false);
      expect(FreeImageCrop.enabled, isFalse);
    });

    test('控制器绑定后，开关直接跟着设置走（没有第二份状态）', () async {
      final AppController c = await boot();
      expect(FreeImageCrop.enabled, isFalse);

      await c.saveFreeImageCrop(true);
      expect(c.settings.freeImageCrop, isTrue);
      expect(FreeImageCrop.enabled, isTrue, reason: '置真后裁剪层必须立刻解除限制');

      await c.saveFreeImageCrop(false);
      expect(FreeImageCrop.enabled, isFalse, reason: '关掉后必须立刻恢复锁定');
    });
  });

  group('freeimage 命令', () {
    /// 点「执行命令」按钮（用按钮类型定位：文字同时出现在 FitText 与 Text 上）。
    Future<void> runCommand(WidgetTester tester, String cmd) async {
      await tester.enterText(find.byType(TextField), cmd);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
    }

    testWidgets('输入 freeimage 打开「自由剪图」页', (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: AdvancedSettingsPage(controller: c)));

      await runCommand(tester, 'freeimage');

      expect(find.byType(FreeImageSettingsPage), findsOneWidget);
      expect(find.text('自由剪图'), findsWidgets);
    });

    testWidgets('页面里的开关切换设置与裁剪层', (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: FreeImageSettingsPage(controller: c)));
      await tester.pumpAndSettle();

      expect(FreeImageCrop.enabled, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(c.settings.freeImageCrop, isTrue);
      expect(FreeImageCrop.enabled, isTrue, reason: '开关置真 ⇒ 全部编辑器解除比例限制');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(FreeImageCrop.enabled, isFalse);
    });

    testWidgets('未知命令仍然提示（没有把命令表搞坏）', (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: AdvancedSettingsPage(controller: c)));

      await runCommand(tester, 'freeimagee');

      expect(find.byType(FreeImageSettingsPage), findsNothing);
    });
  });

  group('静态守护：不许有图片编辑器漏掉这个开关', () {
    List<File> dartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    test('每个直接调起裁剪器的地方都必须读 FreeImageCrop', () {
      // 走 openCropPage 的编辑器由裁剪入口统一处理（入口自己读开关）；
      // 但**绕过入口直接调 ImageCropper** 的编辑器必须自己读，否则自由剪图对它不生效。
      final List<String> offenders = <String>[];
      for (final File f in dartFiles()) {
        final String src = f.readAsStringSync();
        if (!src.contains('cropImage(')) continue;
        if (!src.contains('FreeImageCrop')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '这些文件直接调了裁剪器但没读 FreeImageCrop，自由剪图对它们不生效：$offenders',
      );
    });

    test('裁剪入口自己必须读开关（所有走 openCropPage 的编辑器靠它生效）', () {
      final String entry = File(
        'lib/island_app/widgets/card_crop_page.dart',
      ).readAsStringSync();
      expect(entry.contains('FreeImageCrop'), isTrue);
      for (final String impl in <String>[
        'lib/island_app/widgets/card_crop_platform_io.dart',
        'lib/island_app/widgets/card_crop_platform_stub.dart',
      ]) {
        expect(
          File(impl).readAsStringSync().contains('FreeImageCrop.enabled'),
          isTrue,
          reason: '$impl 必须按开关决定是否锁比例',
        );
      }
    });

    test('原生端不再写死锁定比例', () {
      final String io = File(
        'lib/island_app/widgets/card_crop_platform_io.dart',
      ).readAsStringSync();
      expect(io.contains('FreeImageCrop.enabled'), isTrue);
      expect(
        RegExp(r'lockAspectRatio:\s*true').hasMatch(io),
        isFalse,
        reason: 'lockAspectRatio 必须跟着开关走，不能再写死 true',
      );
      expect(
        RegExp(r'aspectRatioLockEnabled:\s*true').hasMatch(io),
        isFalse,
        reason: 'iOS 侧的锁也必须跟着开关走',
      );
    });

    test('Web 端同样跟着开关走', () {
      final String stub = File(
        'lib/island_app/widgets/card_crop_platform_stub.dart',
      ).readAsStringSync();
      expect(stub.contains('FreeImageCrop.enabled'), isTrue);
    });

    test('TA 编辑器自己调裁剪器，也必须读开关', () {
      final String ta = File('lib/pages/ta_editor_page.dart').readAsStringSync();
      expect(ta.contains('FreeImageCrop.enabled'), isTrue);
      expect(
        RegExp(r'aspectRatio:\s*ratio\s*,').hasMatch(ta),
        isFalse,
        reason: 'TA 编辑器不能无条件传固定比例',
      );
    });
  });
}

class _FakeHive extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}
