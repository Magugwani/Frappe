import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import 'custom_app_bar.dart';

/// Placeholder screen for features not yet implemented.
/// Every bottom-nav tab must navigate somewhere — this prevents dead buttons.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const ComingSoonScreen({
    super.key,
    required this.title,
    this.message = 'This feature is coming in the next development phase.',
    this.icon = Icons.construction_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: title),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 64, color: AppColors.accent),
              ),
              const SizedBox(height: 24),
              Text(title, style: AppTypography.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withAlpha(60)),
                ),
                child: Text(
                  'Planned: Notification System Phase',
                  style: AppTypography.labelMedium.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
