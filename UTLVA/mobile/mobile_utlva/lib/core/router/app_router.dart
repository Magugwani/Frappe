import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/admin_dashboard.dart';
import '../../features/dashboard/screens/coordinator_dashboard.dart';
import '../../features/dashboard/screens/lecturer_dashboard.dart';
import '../../features/dashboard/screens/student_dashboard.dart';
// Timetable screens
import '../../features/timetable/screens/coordinator_timetable_screen.dart';
import '../../features/timetable/screens/lecturer_timetable_screen.dart';
import '../../features/timetable/screens/student_timetable_screen.dart';
import '../../features/timetable/screens/timetable_generation_screen.dart';
import '../../features/timetable/screens/timetable_validation_screen.dart';
import '../../features/timetable/screens/timetable_publishing_screen.dart';
import '../../features/timetable/screens/conflict_resolution_screen.dart';
import '../../features/timetable/screens/emergency_session_screen.dart';
// Academic setup screens
import '../../features/academics/screens/academic_year_screen.dart';
import '../../features/academics/screens/teaching_period_screen.dart';
import '../../features/academics/screens/semester_screen.dart';
import '../../features/academics/screens/department_screen.dart';
import '../../features/academics/screens/programme_screen.dart';
import '../../features/academics/screens/student_group_screen.dart';
import '../../features/academics/screens/course_screen.dart';
import '../../features/academics/screens/lecturer_screen.dart';
// Venue screens
import '../../features/venues/screens/building_screen.dart';
import '../../features/venues/screens/venue_screen.dart';
import '../../features/venues/screens/venue_status_screen.dart';
import '../../features/venues/screens/venue_map_screen.dart';
import '../../features/venues/screens/venue_detail_screen.dart';
import '../../features/venues/screens/venue_list_screen.dart';
import '../../features/venues/models/venue_map_data.dart';
// FR-1–5 — User Management, Audit Logs, System Settings, Monitor
import '../../features/admin/screens/user_management_screen.dart';
import '../../features/admin/screens/audit_log_screen.dart';
import '../../features/admin/screens/system_settings_screen.dart';
import '../../features/admin/screens/system_monitor_screen.dart';
// FR-1 — Forgot Password / Reset Password
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
// SRS 3.2 — University timetable (static official + live with venue status)
import '../../features/timetable/screens/university_timetable_screen.dart';
// SRS 3.6 — Student emergency sessions
import '../../features/timetable/screens/student_emergency_sessions_screen.dart';
// SRS 3.7 — Generic notifications screen (all roles)
import '../../features/notifications/screens/notifications_screen.dart';
// SRS 3.8 — Notification preferences screen (FR-50)
import '../../features/notifications/screens/notification_preferences_screen.dart';
// SRS 3.9 — Bulk enrollment screen (FR-52)
import '../../features/admin/screens/bulk_enrollment_screen.dart';


class AppRouter {
  static GoRouter router(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final status = auth.status;
        final isAuthenticated = auth.isAuthenticated;
        final location = state.uri.toString();

        // ── 1. Hold on splash during session check ───────────────────────────
        if (status == AuthStatus.initial || status == AuthStatus.checking) {
          return location == '/splash' ? null : '/splash';
        }

        // ── 2. Authenticated → send away from public pages ───────────────────
        if (isAuthenticated && (location == '/login' || location == '/splash')) {
          return _dashboardRoute(auth.user!.role);
        }

        // ── 3. Unauthenticated → send to login ───────────────────────────────
        if (!isAuthenticated && location != '/login') return '/login';

        // ── 4. Role-based access guard (FR-3) ────────────────────────────────
        // Prevent wrong roles from accessing restricted screens via direct URL.
        if (isAuthenticated) {
          final role = auth.user?.role ?? '';

          // Admin-only pages
          const adminOnly = ['/admin/audit-logs', '/admin/settings'];
          if (adminOnly.contains(location) && role != 'SYSTEM_ADMIN') {
            return _dashboardRoute(role);
          }

          // Admin + Coordinator only
          const coordinatorPages = [
            '/admin/users', '/timetable/coordinator', '/timetable/generate',
            '/timetable/validate', '/timetable/publish', '/timetable/conflicts',
            '/setup/years', '/setup/periods', '/setup/semesters', '/setup/departments',
            '/setup/programmes', '/setup/groups', '/setup/courses', '/setup/lecturers',
            '/setup/buildings', '/setup/venues',
          ];
          if (coordinatorPages.contains(location) &&
              role != 'SYSTEM_ADMIN' && role != 'COORDINATOR') {
            return _dashboardRoute(role);
          }

          // Lecturer-only page
          if (location == '/timetable/lecturer' && role == 'STUDENT') {
            return '/timetable/student';
          }
        }

        return null;
      },
      routes: [
        // ── Auth ───────────────────────────────────────────────────────────
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),

        // ── Dashboards ────────────────────────────────────────────────────
        GoRoute(path: '/admin/home',       builder: (_, __) => const AdminDashboard()),
        GoRoute(path: '/coordinator/home', builder: (_, __) => const CoordinatorDashboard()),
        GoRoute(path: '/lecturer/home',    builder: (_, __) => const LecturerDashboard()),
        GoRoute(path: '/student/home',     builder: (_, __) => const StudentDashboard()),

        // ── Timetable ─────────────────────────────────────────────────────
        GoRoute(path: '/timetable/coordinator', builder: (_, __) => const CoordinatorTimetableScreen()),
        GoRoute(path: '/timetable/generate',    builder: (_, __) => const TimetableGenerationScreen()),
        GoRoute(path: '/timetable/validate',    builder: (_, __) => const TimetableValidationScreen()),
        GoRoute(path: '/timetable/publish',     builder: (_, __) => const TimetablePublishingScreen()),
        GoRoute(path: '/timetable/conflicts',   builder: (_, __) => const ConflictResolutionScreen()),
        GoRoute(path: '/timetable/lecturer',    builder: (_, __) => const LecturerTimetableScreen()),
        GoRoute(path: '/timetable/student',     builder: (_, __) => const StudentTimetableScreen()),

        // ── Emergency Sessions ────────────────────────────────────────────
        GoRoute(path: '/sessions/emergency', builder: (_, __) => const EmergencySessionScreen()),

        // ── Academic Setup ────────────────────────────────────────────────
        GoRoute(path: '/setup/years',       builder: (_, __) => const AcademicYearScreen()),
        GoRoute(path: '/setup/periods',     builder: (_, __) => const TeachingPeriodScreen()),
        GoRoute(path: '/setup/semesters',   builder: (_, __) => const SemesterScreen()),
        GoRoute(path: '/setup/departments', builder: (_, __) => const DepartmentScreen()),
        GoRoute(path: '/setup/programmes',  builder: (_, __) => const ProgrammeScreen()),
        GoRoute(path: '/setup/groups',      builder: (_, __) => const StudentGroupScreen()),
        GoRoute(path: '/setup/courses',     builder: (_, __) => const CourseScreen()),
        GoRoute(path: '/setup/lecturers',   builder: (_, __) => const LecturerScreen()),
        GoRoute(path: '/setup/buildings',   builder: (_, __) => const BuildingScreen()),
        GoRoute(path: '/setup/venues',      builder: (_, __) => const VenueScreen()),

        // ── Venues ────────────────────────────────────────────────────────
        GoRoute(path: '/venues/map',    builder: (_, __) => const VenueMapScreen()),
        GoRoute(path: '/venues/list',   builder: (_, __) => const VenueListScreen()),
        GoRoute(path: '/venues/status', builder: (_, __) => const VenueStatusScreen()),
        GoRoute(
          path: '/venues/detail/:id',
          builder: (context, state) => VenueDetailScreen(
            venueId: int.parse(state.pathParameters['id']!),
            prefetched: state.extra as VenueMapData?,
          ),
        ),

        // ── FR-1–5: User Management, Monitor, Settings (Admin + Coordinator)
        GoRoute(path: '/admin/users',      builder: (_, __) => const UserManagementScreen()),
        GoRoute(path: '/admin/audit-logs', builder: (_, __) => const AuditLogScreen()),
        GoRoute(path: '/admin/settings',   builder: (_, __) => const SystemSettingsScreen()),
        GoRoute(path: '/admin/monitor',    builder: (_, __) => const SystemMonitorScreen()),
        // ── SRS 3.2: Official (static) + Live (venue status + navigation) ──
        GoRoute(
          path: '/timetable/official',
          builder: (_, __) => const UniversityTimetableScreen(mode: TimetableViewMode.official),
        ),
        GoRoute(
          path: '/timetable/live',
          builder: (_, __) => const UniversityTimetableScreen(mode: TimetableViewMode.live),
        ),
        // ── FR-1: Forgot Password / Reset Password ────────────────────────
        GoRoute(path: '/forgot-password',  builder: (_, __) => const ForgotPasswordScreen()),
        GoRoute(
          path: '/reset-password',
          builder: (_, state) => ResetPasswordScreen(prefillToken: state.extra as String?),
        ),

        // ── FR-41/45: In-app notifications (all roles) ─────────────────────
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),

        // ── FR-42/43: Student emergency sessions ──────────────────────────
        GoRoute(
          path: '/student/emergency-sessions',
          builder: (_, __) => const StudentEmergencySessionsScreen(),
        ),

        // ── FR-50: Notification preferences ───────────────────────────────
        GoRoute(
          path: '/notifications/preferences',
          builder: (_, __) => const NotificationPreferencesScreen(),
        ),

        // ── FR-52: Bulk Enrollment ─────────────────────────────────────────
        GoRoute(
          path: '/admin/bulk-enroll',
          builder: (_, __) => const BulkEnrollmentScreen(),
        ),

        // ── SRS §3.11 Reminder email action deep-links ─────────────────────
        // Email links open these routes; each shows the relevant action
        // directly on the lecturer timetable screen.
        GoRoute(
          path: '/action/confirm',
          builder: (_, state) {
            final entryId = int.tryParse(
                state.uri.queryParameters['entry_id'] ?? '0') ?? 0;
            return LecturerTimetableScreen(autoActionEntryId: entryId, autoAction: 'confirm');
          },
        ),
        GoRoute(
          path: '/action/postpone',
          builder: (_, state) {
            final entryId = int.tryParse(
                state.uri.queryParameters['entry_id'] ?? '0') ?? 0;
            return LecturerTimetableScreen(autoActionEntryId: entryId, autoAction: 'postpone');
          },
        ),
        GoRoute(
          path: '/action/cancel',
          builder: (_, state) {
            final entryId = int.tryParse(
                state.uri.queryParameters['entry_id'] ?? '0') ?? 0;
            return LecturerTimetableScreen(autoActionEntryId: entryId, autoAction: 'cancel');
          },
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    );
  }

  static String _dashboardRoute(String role) {
    return switch (role) {
      'SYSTEM_ADMIN' => '/admin/home',
      'COORDINATOR'  => '/coordinator/home',
      'LECTURER'     => '/lecturer/home',
      _              => '/student/home',
    };
  }
}
