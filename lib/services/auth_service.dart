import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

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
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
  }) async {
    try {
      // 首先检查设备是否支持生物识别或设备凭证
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      
      if (!isDeviceSupported && !canCheckBiometrics) {
        print('Auth: Device does not support authentication');
        return false;
      }

      // 获取可用的生物识别类型
      final List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      print('Auth: Available biometrics: $availableBiometrics');

      // 尝试验证
      final bool result = await _localAuth.authenticate(
        localizedReason: localizedReason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: '身份验证',
            cancelButton: '取消',
            biometricHint: '请验证身份',
            biometricNotRecognized: '验证失败，请重试',
            biometricRequiredTitle: '需要生物识别验证',
            biometricSuccess: '验证成功',
            deviceCredentialsRequiredTitle: '需要设备凭证',
            deviceCredentialsSetupDescription: '请设置设备凭证',
            goToSettingsButton: '去设置',
            goToSettingsDescription: '请在设置中配置生物识别',
          ),
          IOSAuthMessages(
            cancelButton: '取消',
            goToSettingsButton: '去设置',
            goToSettingsDescription: '请在设置中配置生物识别',
            lockOut: '请重新启用生物识别',
          ),
        ],
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: false,
          sensitiveTransaction: true,
          biometricOnly: false,
        ),
      );
      
      print('Auth: Authentication result: $result');
      return result;
    } on PlatformException catch (e) {
      print('Auth: PlatformException - code: ${e.code}, message: ${e.message}');
      if (e.code == auth_error.notAvailable) {
        return false;
      } else if (e.code == auth_error.notEnrolled) {
        return false;
      } else if (e.code == auth_error.passcodeNotSet) {
        return false;
      }
      return false;
    } catch (e) {
      print('Auth: Exception - $e');
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
