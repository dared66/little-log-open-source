import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const pickerKey = String.fromEnvironment('GOOGLE_PICKER_API_KEY');
  static const projectNumber = String.fromEnvironment('GOOGLE_PROJECT_NUMBER');
  static const scopes = ['https://www.googleapis.com/auth/drive.file'];

  static bool get configured => kIsWeb
      ? webClientId.isNotEmpty
      : defaultTargetPlatform == TargetPlatform.iOS
      ? iosClientId.isNotEmpty && webClientId.isNotEmpty
      : webClientId.isNotEmpty;
  static bool get pickerConfigured =>
      pickerKey.isNotEmpty && projectNumber.isNotEmpty;
}
