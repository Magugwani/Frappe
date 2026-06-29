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
import '../../academics/models/student_profile.dart';
import '../../academics/services/academics_service.dart';
import '../../notifications/screens/student_notifications_screen.dart' show StudentNotificationsBanner;
import '../../timetable/services/timetable_service.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _currentIndex = 0;

  final _acService = AcademicsService();
  final _ttService = TimetableService();

  StudentProfile? _profile;
  Map<String, dynamic>? _nextClass;
  bool _loadingNext = false;

  static const _navRoutes = [
    null,
    '/timetable/student',
    '/venues/map',
    '/notifications',
    null,
  ];

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    setState(() => _loadingNext = true);
    try {
      final profile = await _acService.getMyStudentProfile();
      if (mounted && profile != null && profile.isComplete) {
        setState(() => _profile = profile);
        final next = await _ttService.getNextClass(
          programmeId: profile.programmeId!,
          studentGroupId: profile.studentGroupId,
        );
        if (mounted) setState(() => _nextClass = next);
      }
    } catch (_) {
      // Non-critical — dashboard still renders
    } finally {
      if (mounted) setState(() => _loadingNext = false);
    }
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    if (index == 4) {
      _showProfileSheet(context);
      setState(() => _currentIndex = 0);
      return;
    }
    if (index == 0) return;
    final route = _navRoutes[index]!;
    context.push(route).then((_) {
      if (mounted) setState(() => _currentIndex = 0);
    });
  }

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
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildBody(String name) {
    return RefreshIndicator(
      onRefresh: _loadStudentData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ───────────────────────────────────────────────────
            Text('Hello,',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            Text(name, style: AppTypography.headlineLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.statusFree.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Student',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.statusFree),
                  ),
                ),
                if (_profile != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _profile!.programmeName ?? _profile!.programmeCode ?? '',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // ── Next Class card (FR-37) ────────────────────────────────────
            _buildNextClassCard(),
            const SizedBox(height: 14),

            // ── Official timetable ────────────────────────────────────────
            ReusableCard(
              onTap: () => context.push('/timetable/official'),
              backgroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                const Icon(Icons.grid_on_outlined,
                    color: AppColors.textOnPrimary, size: 26),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Official Timetable',
                          style: AppTypography.titleMedium
                              .copyWith(color: AppColors.textOnPrimary)),
                      Text('Published schedule — filter by programme',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.textOnPrimary.withAlpha(200))),
                    ])),
                const Icon(Icons.chevron_right,
                    color: AppColors.textOnPrimary),
              ]),
            ),
            const SizedBox(height: 10),

            // ── Live timetable with venue status ──────────────────────────
            ReusableCard(
              onTap: () => context.push('/timetable/live'),
              backgroundColor: AppColors.accent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                const Icon(Icons.sensors_outlined,
                    color: AppColors.textOnPrimary, size: 26),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Live Timetable',
                          style: AppTypography.titleMedium
                              .copyWith(color: AppColors.textOnPrimary)),
                      Text('Real-time venue status · tap  to navigate',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.textOnPrimary.withAlpha(200))),
                    ])),
                const Icon(Icons.navigation_outlined,
                    size: 18, color: AppColors.textOnPrimary),
                const Icon(Icons.chevron_right,
                    color: AppColors.textOnPrimary),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Quick access ──────────────────────────────────────────────
            Text('Quick Access', style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            _buildQuickActions(),
            const SizedBox(height: 24),

            // ── Emergency Sessions (FR-42) ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Emergency Sessions', style: AppTypography.titleLarge),
                TextButton(
                  onPressed: () => context.push('/student/emergency-sessions'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildEmergencySection(),
            const SizedBox(height: 24),

            // ── Notifications (FR-41) ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Notifications', style: AppTypography.titleLarge),
                TextButton(
                  onPressed: () => context.push('/notifications'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const StudentNotificationsBanner(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Next class card ────────────────────────────────────────────────────────

  Widget _buildNextClassCard() {
    if (_loadingNext && _nextClass == null) {
      return ReusableCard(
        backgroundColor: AppColors.primary,
        child: Row(children: [
          const Icon(Icons.access_time, color: AppColors.textOnPrimary, size: 18),
          const SizedBox(width: 8),
          Text('Next Class',
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textOnPrimary)),
          const SizedBox(width: 12),
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  color: AppColors.textOnPrimary, strokeWidth: 2)),
        ]),
      );
    }

    if (_nextClass == null) {
      return ReusableCard(
        backgroundColor: AppColors.primary,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.access_time, color: AppColors.textOnPrimary, size: 18),
            const SizedBox(width: 8),
            Text('Next Class',
                style: AppTypography.titleMedium
                    .copyWith(color: AppColors.textOnPrimary)),
          ]),
          const SizedBox(height: 12),
          Center(
            child: Column(children: [
              const Icon(Icons.event_available, color: AppColors.accent, size: 36),
              const SizedBox(height: 6),
              Text(
                _profile == null
                    ? 'Set up your profile to see your next class'
                    : 'No upcoming classes this week',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textOnPrimary.withAlpha(180)),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ]),
      );
    }

    final nc = _nextClass!;
    final course = (nc['course_name'] as String?) ?? (nc['course_code'] as String?) ?? '';
    final day = (nc['day_of_week'] as String?) ?? '';
    final start = ((nc['start_time'] as String?) ?? '').substring(0, 5);
    final end = ((nc['end_time'] as String?) ?? '').substring(0, 5);
    final venue = (nc['venue_code'] as String?) ?? (nc['venue_name'] as String?) ?? 'TBA';
    final group = (nc['student_group_name'] as String?) ?? '';

    return GestureDetector(
      onTap: () => context.push('/timetable/student'),
      child: ReusableCard(
        backgroundColor: AppColors.primary,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.access_time, color: AppColors.textOnPrimary, size: 18),
            const SizedBox(width: 8),
            Text('Next Class',
                style: AppTypography.titleMedium
                    .copyWith(color: AppColors.textOnPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(60),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Tap to view timetable',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textOnPrimary)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(course,
              style: AppTypography.titleLarge
                  .copyWith(color: AppColors.textOnPrimary),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.schedule, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            Text('$day  $start – $end',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textOnPrimary.withAlpha(220))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.place_outlined, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(venue,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textOnPrimary.withAlpha(220)),
                  overflow: TextOverflow.ellipsis),
            ),
            if (group.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(group,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.accent)),
            ],
          ]),
        ]),
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final actions = [
      ('My Timetable', Icons.calendar_month_outlined, AppColors.primary,
          '/timetable/student'),
      ('Venue Map', Icons.map_outlined, AppColors.accent, '/venues/map'),
      ('Find Venue', Icons.search_outlined, AppColors.statusBooked,
          '/venues/list'),
      ('Emergency', Icons.warning_amber_outlined, AppColors.statusInUse,
          '/student/emergency-sessions'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: actions.length,
      itemBuilder: (_, i) {
        final a = actions[i];
        return GestureDetector(
          onTap: () => context.push(a.$4),
          child: ReusableCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: a.$3.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(a.$2, color: a.$3, size: 20),
                ),
                const SizedBox(height: 6),
                Text(a.$1,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Emergency sessions preview in dashboard ───────────────────────────────

  Widget _buildEmergencySection() {
    return ReusableCard(
      onTap: () => context.push('/student/emergency-sessions'),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.statusBooked.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              color: AppColors.statusBooked, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Emergency Sessions',
                style: AppTypography.titleMedium),
            Text('View approved extra sessions for your group',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ]),
    );
  }

  // ── Profile sheet ──────────────────────────────────────────────────────────

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
