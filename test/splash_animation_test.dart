import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';
import 'package:dna/pages/splash/splash_animations.dart';
import 'package:dna/pages/splash_page.dart';
import 'package:dna/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开场动画的数据驱动契约：选项来自同一张表、设置存 id、旧存档能迁移。
void main() {
  group('动画注册表', () {
    test('id 唯一，且默认动画排在第一个', () {
      final Set<String> ids = <String>{
        for (final SplashAnimationSpec s in kSplashAnimations) s.id,
      };
      expect(ids.length, kSplashAnimations.length, reason: 'id 不能重复');
      expect(kSplashAnimations.first.id, kDefaultSplashAnimationId);
    });

    test('关闭项时长为 0，其余为正数', () {
      for (final SplashAnimationSpec s in kSplashAnimations) {
        if (s.id == kSplashAnimationOffId) {
          expect(s.enabled, isFalse);
          expect(s.durationMs, 0);
        } else {
          expect(s.enabled, isTrue, reason: '${s.id} 应该能播');
          expect(s.durationMs, greaterThan(0));
        }
      }
    });

    test('每个选项都有给人看的名字与说明', () {
      for (final SplashAnimationSpec s in kSplashAnimations) {
        expect(s.label.trim(), isNotEmpty);
        expect(s.description.trim(), isNotEmpty);
      }
    });

    test('未知 id 回退到默认（旧存档/改过配置都不崩）', () {
      expect(splashAnimationById('不存在').id, kDefaultSplashAnimationId);
      expect(splashAnimationById('').id, kDefaultSplashAnimationId);
    });

    test('已知 id 原样返回', () {
      for (final SplashAnimationSpec s in kSplashAnimations) {
        expect(splashAnimationById(s.id).id, s.id);
      }
    });
  });

  group('设置存取', () {
    test('默认是默认动画，showSplashAnimation 由 id 派生', () {
      final AppSettings s = AppSettings.empty();
      expect(s.splashAnimation, kDefaultSplashAnimationId);
      expect(s.showSplashAnimation, isTrue);
      expect(s.copyWith(splashAnimation: kSplashAnimationOffId).showSplashAnimation,
          isFalse);
    });

    test('patch 写 id', () {
      final AppSettings s = applySettingsPatch(
        AppSettings.empty(),
        'splashAnimation',
        'fade',
      );
      expect(s.splashAnimation, 'fade');
    });

    test('旧布尔键：false 映射成关闭，true 映射成默认动画', () {
      expect(
        applySettingsPatch(AppSettings.empty(), 'showSplashAnimation', false)
            .splashAnimation,
        kSplashAnimationOffId,
      );
      expect(
        applySettingsPatch(
          AppSettings.empty().copyWith(splashAnimation: 'fade'),
          'showSplashAnimation',
          true,
        ).splashAnimation,
        kDefaultSplashAnimationId,
      );
    });

    test('fromJson：新字段优先，旧字段兜底', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{'splashAnimation': 'zoom'})
            .splashAnimation,
        'zoom',
      );
      expect(
        AppSettings.fromJson(<String, dynamic>{'showSplashAnimation': false})
            .splashAnimation,
        kSplashAnimationOffId,
      );
      expect(
        AppSettings.fromJson(<String, dynamic>{'splashAnimation': 'fade', 'showSplashAnimation': false})
            .splashAnimation,
        'fade',
        reason: '新字段在，就不要被旧字段覆盖',
      );
    });

    test('SharedPreferences 迁移：老版本关过的人继续不播', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'show_splash_animation': false,
      });
      final AppSettings s = await SettingsService().load();
      expect(s.splashAnimation, kSplashAnimationOffId);
    });

    test('SharedPreferences：新键存在时以新键为准', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'splash_animation': 'zoom',
        'show_splash_animation': false,
      });
      final AppSettings s = await SettingsService().load();
      expect(s.splashAnimation, 'zoom');
    });
  });

  group('渲染与完成回调', () {
    testWidgets('每段可播动画都会在时长内回调 onComplete', (WidgetTester tester) async {
      for (final SplashAnimationSpec spec in kSplashAnimations) {
        if (!spec.enabled) continue;
        int done = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: SplashPage(animation: spec, onComplete: () => done++),
          ),
        );
        await tester.pump(); // 让控制器起跑
        await tester.pump(Duration(milliseconds: spec.durationMs)); // 跑完
        await tester.pump(); // 处理 whenComplete 的微任务
        await tester.pump(const Duration(milliseconds: 50));
        expect(done, 1, reason: '${spec.id} 没有回调 onComplete');
      }
    });

    testWidgets('关闭项：不挂动画也能自己结束', (WidgetTester tester) async {
      int done = 0;
      final SplashAnimationSpec off = splashAnimationById(kSplashAnimationOffId);
      await tester.pumpWidget(
        MaterialApp(home: SplashPage(animation: off, onComplete: () => done++)),
      );
      await tester.pump();
      expect(done, 1);
    });
  });
}
