import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/admin_dashboard.dart';
import '../../features/dashboard/screens/coordinator_dashboard.dart';
import '../../features/dashboard/screens/lecturer_dashboard.dart';
import '../../features/dashboard/screens/student_dashboard.dart';
// Phase 2 — Academic & Venue management screens
import '../../features/timetable/screens/coordinator_timetable_screen.dart';
import '../../features/timetable/screens/lecturer_timetable_screen.dart';
import '../../features/timetable/screens/student_timetable_screen.dart';
import '../../features/timetable/screens/timetable_generation_screen.dart';
import '../../features/timetable/screens/timetable_validation_screen.dart';
import '../../features/timetable/screens/timetable_publishing_screen.dart';
import '../../features/timetable/screens/conflict_resolution_screen.dart';
import '../../features/academics/screens/academic_year_screen.dart';
import '../../features/academics/screens/teaching_period_screen.dart';
import '../../features/academics/screens/semester_screen.dart';
import '../../features/academics/screens/department_screen.dart';
import '../../features/academics/screens/programme_screen.dart';
import '../../features/academics/screens/student_group_screen.dart';
import '../../features/academics/screens/course_screen.dart';
import '../../features/academics/screens/lecturer_screen.dart';
import '../../features/venues/screens/building_screen.dart';
import '../../features/venues/screens/venue_screen.dart';

class AppRouter {
  static GoRouter router(AuthProvider auth) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final status = auth.status;
        final isAuthenticated = auth.isAuthenticated;
        final location = state.uri.toString();

        // ── 1. App startup: hold on splash while session is being checked ────
        //
        // Triggered only when status == initial (before check) or
        // checking (checkSession() in progress).
        //
        // login() and logout() use _isSubmitting and never set status to
        // initial/checking, so this block NEVER fires during login.
        if (status == AuthStatus.initial || status == AuthStatus.checking) {
          return location == '/splash' ? null : '/splash';
        }

        // ── 2. Authenticated: send away from public routes to dashboard ──────
        //
        // Fires when:
        //   - checkSession() finds a valid stored token → /splash → dashboard
        //   - login() succeeds → /login → dashboard
        if (isAuthenticated &&
            (location == '/login' || location == '/splash')) {
          return _dashboardRoute(auth.user!.role);
        }

        // ── 3. Unauthenticated: redirect any non-login route to /login ───────
        //
        // NOTE: /splash is intentionally NOT excluded here.
        // When checkSession() completes with unauthenticated and the app is
        // still on /splash, this rule fires and sends the user to /login.
        // This is the fix for the "stuck on splash" bug.
        if (!isAuthenticated && location != '/login') {
          return '/login';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/admin/home',
          builder: (context, state) => const AdminDashboard(),
        ),
        GoRoute(
          path: '/coordinator/home',
          builder: (context, state) => const CoordinatorDashboard(),
        ),
        GoRoute(
          path: '/lecturer/home',
          builder: (context, state) => const LecturerDashboard(),
        ),
        GoRoute(
          path: '/student/home',
          builder: (context, state) => const StudentDashboard(),
        ),
        // Phase 3 — Timetable routes
        GoRoute(path: '/timetable/coordinator', builder: (context, state) => const CoordinatorTimetableScreen()),
        GoRoute(path: '/timetable/generate', builder: (context, state) => const TimetableGenerationScreen()),
        GoRoute(path: '/timetable/validate', builder: (context, state) => const TimetableValidationScreen()),
        GoRoute(path: '/timetable/publish', builder: (context, state) => const TimetablePublishingScreen()),
        GoRoute(path: '/timetable/conflicts', builder: (context, state) => const ConflictResolutionScreen()),
        GoRoute(path: '/timetable/lecturer', builder: (context, state) => const LecturerTimetableScreen()),
        GoRoute(path: '/timetable/student', builder: (context, state) => const StudentTimetableScreen()),
        // Phase 2 — Academic setup routes (Coordinator + Admin)
        GoRoute(path: '/setup/years', builder: (context, state) => const AcademicYearScreen()),
        GoRoute(path: '/setup/periods', builder: (context, state) => const TeachingPeriodScreen()),
        GoRoute(path: '/setup/semesters', builder: (context, state) => const SemesterScreen()),
        GoRoute(path: '/setup/departments', builder: (context, state) => const DepartmentScreen()),
        GoRoute(path: '/setup/programmes', builder: (context, state) => const ProgrammeScreen()),
        GoRoute(path: '/setup/groups', builder: (context, state) => const StudentGroupScreen()),
        GoRoute(path: '/setup/courses', builder: (context, state) => const CourseScreen()),
        GoRoute(path: '/setup/lecturers', builder: (context, state) => const LecturerScreen()),
        GoRoute(path: '/setup/buildings', builder: (context, state) => const BuildingScreen()),
        GoRoute(path: '/setup/venues', builder: (context, state) => const VenueScreen()),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    );
  }

  static String _dashboardRoute(String role) {
    switch (role) {
      case 'SYSTEM_ADMIN':
        return '/admin/home';
      case 'COORDINATOR':
        return '/coordinator/home';
      case 'LECTURER':
        return '/lecturer/home';
      default:
        return '/student/home';
    }
  }
}
