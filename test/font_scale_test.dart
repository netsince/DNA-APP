import 'dart:io';

import 'package:dna/main.dart';
import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/settings/appearance_display_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/font_scale.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局字号档位的契约：档位表、越界夹取、设置项往返、以及**真的注入到
/// MediaQuery**（主应用与社区共用同一个 textScaler）。
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

Future<AppController> boot({int fontSizeStep = 0}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'completed_oobe': true,
    'show_splash_animation': false,
    'enable_community': false,
    'font_size_step': fontSizeStep,
  });
  final AppController controller = AppController(
    settingsService: SettingsService(),
    openAiService: OpenAiService(),
    taService: TaService(),
    hiveService: _FakeHive(),
  );
  await controller.initialize();
  return controller;
}

void main() {
  group('档位表 AppFontScale', () {
    test('0 是跟随系统，且不提供倍率', () {
      expect(AppFontScale.followSystem, 0);
      expect(AppFontScale.scaleOf(0), isNull);
      expect(AppFontScale.textScalerOf(0), isNull);
      expect(AppFontScale.labelOf(0), '跟随系统');
    });

    test('1..5 严格递增（从最小到最大）', () {
      final List<double> scales = <double>[
        for (int i = 1; i <= AppFontScale.maxStep; i++) AppFontScale.scaleOf(i)!,
      ];
      expect(scales.length, AppFontScale.maxStep);
      for (int i = 1; i < scales.length; i++) {
        expect(scales[i], greaterThan(scales[i - 1]), reason: '第 $i 档应大于前一档');
      }
      // 从小到大跨越幅度合理：最小 < 基准 1.0 < 最大
      expect(scales.first, lessThan(1.0));
      expect(scales.last, greaterThan(1.0));
    });

    test('每档都有名字，且和倍率表一样长', () {
      expect(AppFontScale.labels.length, AppFontScale.maxStep + 1);
      for (int i = 0; i <= AppFontScale.maxStep; i++) {
        expect(AppFontScale.labelOf(i).isNotEmpty, isTrue);
      }
    });

    test('越界档位夹到合法范围（旧备份/手改偏好不崩）', () {
      expect(AppFontScale.clampStep(-3), 0);
      expect(AppFontScale.clampStep(99), AppFontScale.maxStep);
      expect(AppFontScale.labelOf(99), AppFontScale.labelOf(AppFontScale.maxStep));
      expect(AppFontScale.scaleOf(-1), isNull);
    });

    test('档位转成 TextScaler 是线性倍率', () {
      final TextScaler scaler = AppFontScale.textScalerOf(3)!;
      expect(scaler.scale(100), closeTo(AppFontScale.scaleOf(3)! * 100, 0.001));
    });
  });

  group('设置项 fontSizeStep', () {
    test('默认跟随系统', () {
      expect(AppSettings.empty().fontSizeStep, AppFontScale.followSystem);
    });

    test('copyWith 可设置档位', () {
      expect(AppSettings.empty().copyWith(fontSizeStep: 4).fontSizeStep, 4);
    });

    test('toJson / fromJson 往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(fontSizeStep: 2);
      expect(AppSettings.fromJson(s.toJson()).fontSizeStep, 2);
    });

    test('缺失字段回退跟随系统（旧备份恢复不报错）', () {
      final Map<String, dynamic> json = AppSettings.empty().toJson();
      json.remove('fontSizeStep');
      expect(AppSettings.fromJson(json).fontSizeStep, 0);
    });
  });

  group('注入', () {
    testWidgets('选 3 档：主界面拿到 1.15 倍的 textScaler（社区同一个值）', (WidgetTester tester) async {
      final AppController controller = await boot(fontSizeStep: 3);
      await tester.pumpWidget(DnaApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final TextScaler scaler =
          MediaQuery.textScalerOf(tester.element(find.byType(AppSectionShell)));
      expect(
        scaler.scale(100),
        closeTo(AppFontScale.scaleOf(3)! * 100, 0.001),
      );
    });

    testWidgets('0 档（跟随系统）：不覆盖，沿用环境里的倍率', (WidgetTester tester) async {
      final AppController controller = await boot(fontSizeStep: 0);
      await tester.pumpWidget(DnaApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final TextScaler scaler =
          MediaQuery.textScalerOf(tester.element(find.byType(AppSectionShell)));
      expect(scaler.scale(100), closeTo(100, 0.001));
    });

    testWidgets('设置页滑块：onChangeEnd 落库，拖动即生效', (WidgetTester tester) async {
      final AppController controller = await boot();
      await tester.pumpWidget(
        MaterialApp(home: AppearanceDisplayPage(controller: controller)),
      );
      await tester.pump();

      final Finder sliderFinder = find.byWidgetPredicate(
        (Widget w) =>
            w is Slider && w.max == AppFontScale.maxStep.toDouble(),
      );
      await tester.dragUntilVisible(
        sliderFinder,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      final Slider slider = tester.widget<Slider>(sliderFinder);
      expect(slider.value, 0, reason: '默认跟随系统');
      slider.onChangeEnd!(4);
      await tester.pumpAndSettle();
      expect(controller.settings.fontSizeStep, 4);
    });
  });

  group('结构约束（字号只允许来自令牌）', () {
    test('lib 下不再出现裸数字 fontSize', () {
      final List<String> offenders = <String>[];
      final RegExp re = RegExp(r'fontSize: *[0-9]');
      for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        for (final RegExpMatch m in re.allMatches(e.readAsStringSync())) {
          offenders.add('${e.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: '字号必须走 AppFontSize 六档：\n${offenders.join('\n')}');
    });

    test('lib 下不再出现裸行高 height: 1.x', () {
      final List<String> offenders = <String>[];
      final RegExp re = RegExp(r'height: *1\.[0-9]');
      for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        for (final RegExpMatch m in re.allMatches(e.readAsStringSync())) {
          offenders.add('${e.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: '行高必须走 AppLineHeight 三档：\n${offenders.join('\n')}');
    });

    test('倍率只允许出自 AppFontScale（两个合法构造点：令牌 + 过渡插值）', () {
      // 只有两个地方可以构造 TextScaler：
      //  · theme/font_scale.dart      —— 档位 → 倍率的唯一来源
      //  · widgets/animated_font_scale.dart —— 换档时在**两个 AppFontScale 值之间**插值
      // 其余任何地方自己拼 TextScaler，都会绕开档位体系、让"跟随系统"失效。
      const Set<String> allowed = <String>{
        'theme/font_scale.dart',
        'widgets/animated_font_scale.dart',
      };
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String path = e.path.replaceAll('\\', '/');
        if (allowed.any(path.endsWith)) continue;
        if (e.readAsStringSync().contains('TextScaler.linear')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty, reason: '倍率只允许由 AppFontScale 产出');
    });

    test('过渡插值的两端必须取自 AppFontScale（不许自己写死倍率）', () {
      final String src =
          File('lib/widgets/animated_font_scale.dart').readAsStringSync();
      expect(src.contains('AppFontScale.scaleOf'), isTrue);
      // 插值只允许作用在"当前值 → 目标值"之间，不允许出现字面量倍率。
      expect(RegExp(r'TextScaler\.linear\(\s*[0-9]').hasMatch(src), isFalse,
          reason: '过渡组件里不许出现写死的倍率');
    });
  });
}
