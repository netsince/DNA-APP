import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/app_settings.dart';

/// 「请求超时」设置项的持久化与向后兼容。
///
/// 背景：补全请求的超时原本是写死的 20 秒（`LlmServiceBase.completionTimeout`），
/// 带思考的模型思考 20 秒以上就会直接报 `TimeoutException`（非流式调用里它是总时长上限）。
/// 现在改成可在「AI 服务 → ⋮ → 其他 → 请求超时」里调整。
///
/// 这里守住三件事：默认值仍是 20（**不改变老用户行为**）、能存能读、
/// 老版本设置文件里没有这个键时回退到 20。
void main() {
  group('requestTimeoutSeconds 设置项', () {
    test('默认 20 秒：不改变既有行为', () {
      expect(AppSettings.empty().requestTimeoutSeconds, 20);
      // 老设置文件（还没有这个键）也要回退到 20，而不是 0 或崩溃。
      expect(AppSettings.fromJson(<String, dynamic>{}).requestTimeoutSeconds, 20);
      expect(
        AppSettings.fromJson(<String, dynamic>{'summaryWordThreshold': 6000})
            .requestTimeoutSeconds,
        20,
      );
    });

    test('copyWith 能改，toJson/fromJson 能往返', () {
      final AppSettings changed =
          AppSettings.empty().copyWith(requestTimeoutSeconds: 120);
      expect(changed.requestTimeoutSeconds, 120);

      final AppSettings restored = AppSettings.fromJson(changed.toJson());
      expect(restored.requestTimeoutSeconds, 120);
    });

    test('序列化里确实带上了这个键', () {
      final Map<String, dynamic> json =
          AppSettings.empty().copyWith(requestTimeoutSeconds: 90).toJson();
      expect(json['requestTimeoutSeconds'], 90);
    });
  });
}
