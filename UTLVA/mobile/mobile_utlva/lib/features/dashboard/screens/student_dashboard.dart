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

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'My Dashboard',
        onProfileTap: () => _showProfileSheet(context),
      ),
      body: _buildBody(user?.fullName ?? ''),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.student,
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
          Text('Hello,',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          Text(name, style: AppTypography.headlineLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.statusFree.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Student',
              style: AppTypography.labelMedium.copyWith(color: AppColors.statusFree),
            ),
          ),
          const SizedBox(height: 28),
          _buildNextClassCard(),
          const SizedBox(height: 16),
          ReusableCard(
            onTap: () => context.push('/timetable/student'),
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Class Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('View your class schedule grid', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Quick Access', style: AppTypography.titleLarge),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 24),
          Text('Recent Notifications', style: AppTypography.titleLarge),
          const SizedBox(height: 12),
          _buildNotificationsPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildNextClassCard() {
    return ReusableCard(
      backgroundColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, color: AppColors.textOnPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Next Class',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                const Icon(Icons.event_available, color: AppColors.accent, size: 40),
                const SizedBox(height: 8),
                Text(
                  'No upcoming classes',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textOnPrimary.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      ('My Timetable', Icons.calendar_month_outlined, AppColors.primary, '/timetable/student'),
      ('Venue Map', Icons.map_outlined, AppColors.accent, '/venues/map'),
      ('Find Venue', Icons.search_outlined, AppColors.statusBooked, '/venues/list'),
    ];
    return Row(
      children: List.generate(actions.length, (i) {
        final a = actions[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < actions.length - 1 ? 10 : 0),
            child: ReusableCard(
              onTap: () => context.push(a.$4),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: a.$3.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(a.$2, color: a.$3, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(a.$1, textAlign: TextAlign.center, style: AppTypography.labelMedium),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNotificationsPlaceholder() {
    return ReusableCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              const Icon(Icons.notifications_none, size: 36, color: AppColors.textSecondary),
              const SizedBox(height: 8),
              Text('No notifications yet', style: AppTypography.bodySmall),
            ],
          ),
        ),
      ),
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
