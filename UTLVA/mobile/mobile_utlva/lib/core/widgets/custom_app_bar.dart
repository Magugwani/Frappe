import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final List<Widget>? extraActions;
  final Widget? leading;
  final bool showBackButton;

  const CustomAppBar({
    super.key,
    required this.title,
    this.onNotificationTap,
    this.onProfileTap,
    this.extraActions,
    this.leading,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.secondary,
      elevation: 0,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textOnPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : leading ??
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'U',
                      style: TextStyle(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'UTLVA',
            style: AppTypography.caption.copyWith(
              color: AppColors.textOnPrimary.withAlpha(180),
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textOnPrimary,
              fontSize: 15,
            ),
          ),
        ],
      ),
      actions: [
        if (extraActions != null) ...extraActions!,
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: AppColors.textOnPrimary),
          tooltip: 'Notifications',
          onPressed: onNotificationTap ?? () {},
        ),
        IconButton(
          icon: const Icon(Icons.account_circle_outlined, color: AppColors.textOnPrimary),
          tooltip: 'Profile',
          onPressed: onProfileTap ?? () {},
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
