import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';

class ProfileSheet extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final VoidCallback onLogout;

  const ProfileSheet({
    super.key,
    required this.name,
    required this.email,
    required this.role,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.primary,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: AppTypography.headlineLarge.copyWith(color: AppColors.textOnPrimary),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, style: AppTypography.titleLarge),
          Text(email, style: AppTypography.bodySmall),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role,
              style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: Text(
              'Sign Out',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
            ),
            onTap: onLogout,
          ),
          const SizedBox(height: 8),
          // Bottom safe-area padding so content clears the home indicator on mobile
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
