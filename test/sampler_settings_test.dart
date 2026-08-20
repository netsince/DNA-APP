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

  group('AppSettings 聊天界面', () {
    test('对话框透明度默认完全不透明（100）', () {
      final AppSettings s = AppSettings.empty();
      expect(s.chatBubbleOpacity, 100);
      expect(s.chatMaskStrength, 75);
    });

    test('chatBubbleOpacity 序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(chatBubbleOpacity: 40);
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.chatBubbleOpacity, 40);
    });

    test('chatBubbleOpacity 缺失字段回退默认（100）', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.chatBubbleOpacity, 100);
    });

    test('半屏聊天默认关闭', () {
      final AppSettings s = AppSettings.empty();
      expect(s.halfScreenChat, isFalse);
      expect(s.dynamicHalfScreen, isFalse);
    });

    test('halfScreenChat 序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(
        halfScreenChat: true,
        dynamicHalfScreen: true,
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.halfScreenChat, isTrue);
      expect(back.dynamicHalfScreen, isTrue);
    });

    test('halfScreenChat 缺失字段回退默认（false）', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.halfScreenChat, isFalse);
      expect(back.dynamicHalfScreen, isFalse);
    });
  });

  group('AppSettings 消息气泡快捷按钮', () {
    test('4 个快捷按钮默认开启', () {
      final AppSettings s = AppSettings.empty();
      expect(s.showMessageAvatar, isTrue);
      expect(s.showMessageRetry, isTrue);
      expect(s.showMessageCopy, isTrue);
      expect(s.showMessageContinue, isTrue);
    });

    test('快捷按钮开关序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(
        showMessageAvatar: false,
        showMessageRetry: false,
        showMessageCopy: false,
        showMessageContinue: false,
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.showMessageAvatar, isFalse);
      expect(back.showMessageRetry, isFalse);
      expect(back.showMessageCopy, isFalse);
      expect(back.showMessageContinue, isFalse);
    });

    test('快捷按钮开关缺失字段回退默认（true）', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.showMessageAvatar, isTrue);
      expect(back.showMessageRetry, isTrue);
      expect(back.showMessageCopy, isTrue);
      expect(back.showMessageContinue, isTrue);
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

  group('AppSettings DeepSeek 思考模式', () {
    test('默认开启思考且强度为 high', () {
      final AppSettings s = AppSettings.empty();
      expect(s.deepseekThinkingEnabled, isTrue);
      expect(s.deepseekThinkingEffort, 'high');
    });

    test('思考模式字段序列化往返一致', () {
      final AppSettings s = AppSettings.empty().copyWith(
        deepseekThinkingEnabled: false,
        deepseekThinkingEffort: 'max',
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.deepseekThinkingEnabled, isFalse);
      expect(back.deepseekThinkingEffort, 'max');
    });

    test('思考模式字段缺失回退默认值', () {
      final AppSettings back =
          AppSettings.fromJson(<String, dynamic>{'provider': 'openai'});
      expect(back.deepseekThinkingEnabled, isTrue);
      expect(back.deepseekThinkingEffort, 'high');
    });
  });
}
