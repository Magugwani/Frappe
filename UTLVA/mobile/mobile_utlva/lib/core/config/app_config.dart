import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class AppConfig {
  AppConfig._();

  // Set this to true when using your TECNO phone, false for emulator
  static const bool isPhysicalPhone = true;

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    
    if (Platform.isAndroid) {
      // Switches cleanly between physical USB and computer virtual layers
      return isPhysicalPhone ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';
    }
    
    return 'http://localhost:8000';
  }

  static const String apiPrefix = '/api';

  static String get authLogin => '$baseUrl$apiPrefix/auth/login/';
  static String get authLogout => '$baseUrl$apiPrefix/auth/logout/';
  static String get authRefresh => '$baseUrl$apiPrefix/auth/token/refresh/';
  static String get authProfile => '$baseUrl$apiPrefix/auth/profile/';
  static String get authVerify => '$baseUrl$apiPrefix/auth/verify/';
}
