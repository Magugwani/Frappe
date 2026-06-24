import 'package:flutter/material.dart';
import '../config/institution_config.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import 'institution_logo.dart';

/// Global UTLVA branding app bar.
///
/// Layout:
///   LEFT → CENTER : System full name + institution name (from [settings])
///   RIGHT         : Institution logo (from [settings])
///
/// Neither the institution name nor the logo is hardcoded here.
/// They come exclusively from [InstitutionSettings].
///
/// Usage:
///   Scaffold(
///     appBar: CustomUTLVAAppBar(settings: InstitutionSettings.defaults),
///     ...
///   )
class CustomUTLVAAppBar extends StatelessWidget implements PreferredSizeWidget {
  final InstitutionSettings settings;

  const CustomUTLVAAppBar({
    super.key,
    this.settings = InstitutionSettings.defaults,
  });

  static const double _toolbarHeight = 68;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.secondary,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: _toolbarHeight,
      titleSpacing: 20,

      // LEFT → CENTER: system name + institution name
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'University Timetable and Local Venue Arrangement (UTLVA)',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textOnPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            settings.institutionName,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textOnPrimary.withAlpha(200),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),

      // RIGHT: institution logo
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: InstitutionLogo(
            settings: settings,
            size: 44,
            placeholderBackground: AppColors.surface,
            placeholderForeground: AppColors.secondary,
          ),
        ),
      ],
    );
  }
}
