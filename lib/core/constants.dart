import 'config/app_config.dart';

/// Application-wide constants.
class ApiConstants {
  static String get baseUrl => AppConfig.apiOrigin;
  static String get wsUrl => AppConfig.websocketUrl;
  static String get apiPrefix => AppConfig.apiPathPrefix;
}

class AppConstants {
  static const String appName = 'v_monitor';
}
