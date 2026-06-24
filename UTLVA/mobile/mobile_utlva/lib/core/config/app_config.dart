import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    // Android emulator maps 10.0.2.2 → host machine's localhost
    return 'http://10.0.2.2:8000';
  }

  static const String apiPrefix = '/api';

  static String get authLogin => '$baseUrl$apiPrefix/auth/login/';
  static String get authLogout => '$baseUrl$apiPrefix/auth/logout/';
  static String get authRefresh => '$baseUrl$apiPrefix/auth/token/refresh/';
  static String get authProfile => '$baseUrl$apiPrefix/auth/profile/';
  static String get authVerify => '$baseUrl$apiPrefix/auth/verify/';
}
