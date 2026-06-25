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

class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({super.key});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Lecturer Dashboard',
        onProfileTap: () => _showProfileSheet(context),
      ),
      body: _buildBody(user?.fullName ?? ''),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.lecturer,
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
          Text('Good day,',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          Text(name, style: AppTypography.headlineLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Lecturer',
              style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 28),
          _buildTodayCard(),
          const SizedBox(height: 16),
          ReusableCard(
            onTap: () => context.push('/timetable/lecturer'),
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('View your assigned teaching schedule', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Quick Actions', style: AppTypography.titleLarge),
          const SizedBox(height: 12),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildTodayCard() {
    return ReusableCard(
      backgroundColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, color: AppColors.textOnPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                "Today's Sessions",
                style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'No sessions scheduled for today',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textOnPrimary.withAlpha(180),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      ('View Timetable', Icons.calendar_month_outlined, AppColors.primary, '/timetable/lecturer'),
      ('Create Emergency Session', Icons.add_alert_outlined, AppColors.statusExpired, '/sessions/emergency'),
      ('Find a Venue', Icons.search_outlined, AppColors.accent, '/venues/list'),
      ('Venue Map', Icons.map_outlined, AppColors.statusFree, '/venues/map'),
    ];
    return Column(
      children: actions.map((a) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ReusableCard(
            onTap: () => context.push(a.$4),
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
