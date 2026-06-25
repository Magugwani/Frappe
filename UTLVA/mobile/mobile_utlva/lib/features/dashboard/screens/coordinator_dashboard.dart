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

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Coordinator Dashboard',
        onProfileTap: () => _showProfileSheet(context),
      ),
      body: _buildBody(user?.fullName ?? ''),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.coordinator,
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
              color: AppColors.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Timetable Coordinator',
              style: AppTypography.labelMedium.copyWith(color: AppColors.accent),
            ),
          ),
          const SizedBox(height: 28),
          _buildStatsRow(),
          const SizedBox(height: 16),
          // Phase 7 — Publish Timetable
          ReusableCard(
            onTap: () => context.push('/timetable/publish'),
            backgroundColor: AppColors.statusBooked,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.publish_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Publish Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Manage lifecycle: Draft → Validated → Published', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),
          // Phase 5 — Auto-Generate Timetable
          ReusableCard(
            onTap: () => context.push('/timetable/generate'),
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.auto_fix_high, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Auto-Generate Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Automatically assign courses to periods and venues', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),
          // Phase 6 — Validate Timetable
          ReusableCard(
            onTap: () => context.push('/timetable/validate'),
            backgroundColor: AppColors.statusFree,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Validate Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Detect venue, lecturer and group conflicts', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),
          // Phase 3 — Timetable shortcut
          ReusableCard(
            onTap: () => context.push('/timetable/coordinator'),
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Timetable Management', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('View, edit and publish timetable entries', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),
          // Phase 8 — Emergency Sessions
          ReusableCard(
            onTap: () => context.push('/sessions/emergency'),
            backgroundColor: AppColors.statusExpired,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.emergency_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Emergency Sessions', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Review and approve emergency session requests', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
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

  Widget _buildStatsRow() {
    final stats = [
      ('Venues', '0', Icons.location_city_outlined, AppColors.primary),
      ('Timetables', '0', Icons.calendar_month_outlined, AppColors.accent),
      ('Users', '0', Icons.group_outlined, AppColors.statusFree),
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
    final sections = [
      {
        'header': 'Academic Setup',
        'icon': Icons.school_outlined,
        'color': AppColors.primary,
        'items': [
          ('Academic Years', Icons.calendar_today_outlined, '/setup/years'),
          ('Semesters', Icons.date_range_outlined, '/setup/semesters'),
          ('Teaching Periods', Icons.schedule_outlined, '/setup/periods'),
          ('Departments', Icons.business_outlined, '/setup/departments'),
          ('Programmes', Icons.school_outlined, '/setup/programmes'),
          ('Student Groups', Icons.group_outlined, '/setup/groups'),
          ('Courses', Icons.menu_book_outlined, '/setup/courses'),
          ('Lecturers', Icons.person_outlined, '/setup/lecturers'),
        ],
      },
      {
        'header': 'Venue Management',
        'icon': Icons.location_city_outlined,
        'color': AppColors.accent,
        'items': [
          ('Venue Map', Icons.map_outlined, '/venues/map'),
          ('Find a Venue', Icons.search_outlined, '/venues/list'),
          ('Venue Status Monitor', Icons.monitor_heart_outlined, '/venues/status'),
          ('Buildings', Icons.business_outlined, '/setup/buildings'),
          ('Venues (CRUD)', Icons.meeting_room_outlined, '/setup/venues'),
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        final header = section['header'] as String;
        final items = section['items'] as List<(String, IconData, String)>;
        final color = section['color'] as Color;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(header, style: AppTypography.titleLarge.copyWith(color: color)),
            ),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReusableCard(
                onTap: () => context.push(item.$3),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                    child: Icon(item.$2, color: color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(item.$1, style: AppTypography.titleMedium)),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ]),
              ),
            )),
            const SizedBox(height: 8),
          ],
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
