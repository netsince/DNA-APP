import 'package:dna/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings 高级采样参数', () {
    test('默认值为中性/关闭', () {
      final AppSettings s = AppSettings.empty();
      expect(s.topP, 1.0);
      expect(s.topK, 0.0);
      expect(s.minP, 0.0);
      expect(s.repetitionPenalty, 1.0);
      expect(s.repetitionPenaltySlope, 0.0);
    });

    test('toJson / fromJson 往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        repetitionPenalty: 1.15,
        repetitionPenaltySlope: 0.3,
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.topP, 0.9);
      expect(back.topK, 40.0);
      expect(back.minP, 0.05);
      expect(back.repetitionPenalty, 1.15);
      expect(back.repetitionPenaltySlope, 0.3);
    });

    test('fromJson 缺失字段回退默认值', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.topP, 1.0);
      expect(back.topK, 0.0);
      expect(back.minP, 0.0);
      expect(back.repetitionPenalty, 1.0);
      expect(back.repetitionPenaltySlope, 0.0);
    });

    test('copyWith 不修改其余字段', () {
      final AppSettings s = AppSettings.empty().copyWith(topP: 0.5);
      expect(s.topP, 0.5);
      expect(s.topK, 0.0);
      expect(s.minP, 0.0);
      expect(s.temperature, 0.7);
    });
  });

  group('AppSettings 界面开关', () {
    test('上下文 Token 仪表盘默认关闭', () {
      final AppSettings s = AppSettings.empty();
      expect(s.showTokenDashboard, isFalse);
    });

    test('showTokenDashboard 序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(showTokenDashboard: true);
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.showTokenDashboard, isTrue);
    });

    test('showTokenDashboard 缺失字段回退默认（false）', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.showTokenDashboard, isFalse);
    });
  });

  group('AppSettings 从此处分叉开关', () {
    test('默认关闭', () {
      final AppSettings s = AppSettings.empty();
      expect(s.enableForking, isFalse);
    });

    test('enableForking 序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(enableForking: true);
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.enableForking, isTrue);
    });

    test('enableForking 缺失字段回退默认（false）', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.enableForking, isFalse);
    });
  });
}
