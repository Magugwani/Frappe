import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';

/// The one-and-only UTLVA application bar.
///
/// Per the design-system rule "one consistent AppBar across every role", every
/// screen in the app uses this widget. Differences between screens are
/// expressed through the parameters below — never by writing a raw `AppBar(...)`.
///
/// Parameters
/// ----------
/// [title]              — page title shown under the small UTLVA strapline.
/// [onNotificationTap]  — opens the notifications list. Defaults to no-op.
/// [onProfileTap]       — opens the profile sheet. Defaults to no-op.
/// [extraActions]       — page-specific actions appended BEFORE the notification
///                        and profile icons (e.g. a "Bulk Add" button on a
///                        management screen).
/// [leading]            — overrides the default "U" logo. Ignored when
///                        [showBackButton] is true.
/// [showBackButton]     — true on sub-screens that should pop on tap. Mutually
///                        exclusive with [leading].
/// [showActions]        — when false, hides the notification + profile icons
///                        AND any extraActions. Use only on screens where the
///                        user is not yet authenticated (e.g. the login screen).
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final List<Widget>? extraActions;
  /// When provided, completely replaces the default notification+profile icons.
  /// Use this when a screen needs a custom notification badge or special actions.
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final bool showActions;

  const CustomAppBar({
    super.key,
    required this.title,
    this.onNotificationTap,
    this.onProfileTap,
    this.extraActions,
    this.actions,
    this.leading,
    this.showBackButton = false,
    this.showActions = true,
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
          : leading ?? _buildLogoBadge(),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildLogoBadge() {
    return Padding(
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
    );
  }

  List<Widget> _buildActions() {
    if (!showActions) return const [];
    // Full override — caller manages the complete actions list
    if (actions != null) return [...actions!, const SizedBox(width: 4)];
    return [
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
    ];
  }
}