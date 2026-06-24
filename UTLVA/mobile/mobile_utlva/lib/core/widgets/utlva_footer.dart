import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';

/// Reusable UTLVA branding footer.
///
/// Displays copyright and platform attribution consistently across all screens.
/// Place at the bottom of any scrollable or column layout.
class UtlvaFooter extends StatelessWidget {
  /// When true (default), uses the dark secondary blue background.
  /// Set to false for a light background variant on white screens.
  final bool isDark;

  const UtlvaFooter({super.key, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isDark ? AppColors.secondary : AppColors.background;
    final primaryText = isDark
        ? AppColors.textOnPrimary.withAlpha(200)
        : AppColors.textSecondary;
    final secondaryText = isDark
        ? AppColors.textOnPrimary.withAlpha(140)
        : AppColors.textSecondary.withAlpha(180);

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '© UTLVA — University Timetable and Local Venue Arrangement',
            style: AppTypography.caption.copyWith(color: primaryText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            'Powered by UTLVA Platform',
            style: AppTypography.caption.copyWith(
              color: secondaryText,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
