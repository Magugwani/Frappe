import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/custom_bottom_navigation.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../core/widgets/profile_sheet.dart';
import '../../auth/providers/auth_provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Admin Dashboard',
        onProfileTap: () => _showProfileSheet(context),
      ),
      body: _buildBody(user?.fullName ?? ''),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.systemAdmin,
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }

  Widget _buildBody(String name) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back,',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          Text(name, style: AppTypography.headlineLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'System Administrator',
              style: AppTypography.labelMedium.copyWith(color: AppColors.error),
            ),
          ),
          const SizedBox(height: 28),
          _buildStatsRow(),
          const SizedBox(height: 24),
          Text('Quick Actions', style: AppTypography.titleLarge),
          const SizedBox(height: 12),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = [
      ('Users', '0', Icons.group_outlined, AppColors.primary),
      ('Active', '0', Icons.check_circle_outline, AppColors.statusFree),
      ('Audit', '0', Icons.security_outlined, AppColors.accent),
    ];
    return Row(
      children: List.generate(stats.length, (i) {
        final s = stats[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < stats.length - 1 ? 10 : 0),
            child: ReusableCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.$3, color: s.$4, size: 22),
                  const SizedBox(height: 8),
                  Text(s.$2,
                      style: AppTypography.headlineMedium.copyWith(color: s.$4)),
                  Text(s.$1, style: AppTypography.labelMedium),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      ('Manage Users', Icons.manage_accounts_outlined, AppColors.primary),
      ('System Settings', Icons.settings_outlined, AppColors.accent),
      ('View Audit Logs', Icons.security_outlined, AppColors.textSecondary),
    ];
    return Column(
      children: actions.map((a) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ReusableCard(
            onTap: () {},
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: a.$3.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(a.$2, color: a.$3, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(a.$1, style: AppTypography.titleMedium)),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showProfileSheet(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => ProfileSheet(
        name: user?.fullName ?? '',
        email: user?.email ?? '',
        role: user?.displayRole ?? '',
        onLogout: () async {
          Navigator.pop(sheetContext);
          await context.read<AuthProvider>().logout();
          if (context.mounted) context.go('/login');
        },
      ),
    );
  }
}
