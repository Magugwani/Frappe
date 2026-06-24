import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand 
  static const Color primary = Color(0xFF7BB8E8); // soft sky blue
  static const Color secondary = Color(0xFFA8D0F0); // lighter airy blue
  static const Color accent = Color(0xFF5BA3D9); // deeper but still calm

  // Glass & backgrounds
  static const Color background = Color(0xFFE8F0FE); // very light blue wash
  static const Color surface = Color(0xCCFFFFFF); // semi-transparent white for glass
  static const Color glassBorder = Color(0x66FFFFFF); // frosted edge

  // Text
  static const Color textMain = Color(0xFF1A2A3A);
  static const Color textSecondary = Color(0xFF4A6A8A);
  static const Color textOnPrimary = Color(0xFF1A2A3A);

  // Status
  static const Color statusFree = Color(0xFF2E7D32);
  static const Color statusBooked = Color(0xFF1565C0);
  static const Color statusInUse = Color(0xFFE65100);
  static const Color statusExpired = Color(0xFFC62828);

    // Utility
  static const Color divider = Color(0x33B0C8E0);
  static const Color inputBorder = Color(0x66A0B8D0);
  static const Color shadow = Color(0x3388AACC);
  static const Color error = Color(0xFFC62828);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
}
