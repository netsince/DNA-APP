import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

class AuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isDeviceSupported() async {
    return await _localAuth.isDeviceSupported();
  }

  static Future<bool> canCheckBiometrics() async {
    return await _localAuth.canCheckBiometrics;
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    return await _localAuth.getAvailableBiometrics();
  }

  static Future<bool> authenticate({
    required String localizedReason,
    // v3 移除了这个开关（错误弹窗由系统统一处理），保留形参以免调用点改动。
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    try {
      // 首先检查设备是否支持生物识别或设备凭证
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      
      if (!isDeviceSupported && !canCheckBiometrics) {
        debugPrint('Auth: Device does not support authentication');
        return false;
      }

      // 获取可用的生物识别类型
      final List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('Auth: Available biometrics: $availableBiometrics');

      // 尝试验证
      // local_auth 3.x：提示语只剩「提示 / 标题 / 取消」三项（原来那一长串
      // 分别控制未识别、成功、设备凭证、去设置等细分文案，v3 已并入系统默认），
      // 且 options 取消、biometricOnly 变成顶层参数。
      final bool result = await _localAuth.authenticate(
        localizedReason: localizedReason,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: '身份验证',
            signInHint: '请验证身份',
            cancelButton: '取消',
          ),
          IOSAuthMessages(cancelButton: '取消'),
        ],
        biometricOnly: false,
        sensitiveTransaction: sensitiveTransaction,
        // v3 用 persistAcrossBackgrounding 取代原来的 stickyAuth。
        persistAcrossBackgrounding: stickyAuth,
      );
      
      debugPrint('Auth: Authentication result: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Auth: PlatformException - code: ${e.code}, message: ${e.message}');
      // local_auth 3.x 不再提供 error_codes.dart，错误码就是平台字符串。
      // 三种「设备不具备条件」的情况都按「验证未通过」处理（返回 false），
      // 其余错误也一律 false —— 调用方只需要知道成没成。
      const <String>{'NotAvailable', 'NotEnrolled', 'PasscodeNotSet'};
      return false;
    } catch (e) {
      debugPrint('Auth: Exception - $e');
      return false;
    }
  }

  static Future<bool> authenticateForArchive() async {
    return await authenticate(
      localizedReason: '需要验证身份才能查看归档内容',
      useErrorDialogs: true,
      stickyAuth: false,
    );
  }

  static Future<bool> authenticateForApp() async {
    return await authenticate(
      localizedReason: '需要验证身份才能进入应用',
      useErrorDialogs: true,
      stickyAuth: true,
    );
  }
}
