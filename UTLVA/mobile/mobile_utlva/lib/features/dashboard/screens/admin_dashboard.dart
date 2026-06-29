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
import '../../admin/models/admin_user.dart';
import '../../admin/services/user_management_service.dart';
// ignore: unused_import — imported for completeness; used via router


class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  UserStats? _stats;
  final _service = UserManagementService();

  // Admin bottom nav: Home | Users | Settings | Audit | Profile
  // Index:              0     1              2           3             4
  static const _navRoutes = [null, '/admin/users', '/admin/settings', '/admin/audit-logs', null];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await _service.getUserStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    if (index == 4) { _showProfileSheet(context); setState(() => _currentIndex = 0); return; }
    if (index == 0) return;
    final route = _navRoutes[index]!;
    context.push(route).then((_) { if (mounted) setState(() => _currentIndex = 0); });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Admin Dashboard',
        onProfileTap: () => _showProfileSheet(context),
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome back,',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            Text(user?.fullName ?? '', style: AppTypography.headlineLarge),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('System Administrator',
                  style: AppTypography.labelMedium.copyWith(color: AppColors.error)),
            ),
            const SizedBox(height: 28),
            _buildStatsRow(),
            const SizedBox(height: 24),
            Text('Management', style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            _buildQuickActions(context),
            const SizedBox(height: 24),
            Text('Timetable', style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            _buildTimetableActions(context),
          ]),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.systemAdmin,
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildStatsRow() {
    final total    = _stats?.total    ?? 0;
    final active   = _stats?.active   ?? 0;
    final inactive = _stats?.inactive ?? 0;
    final tiles = [
      ('Total Users', '$total',    Icons.group_outlined,          AppColors.primary),
      ('Active',      '$active',   Icons.check_circle_outline,    AppColors.statusFree),
      ('Inactive',    '$inactive', Icons.block_outlined,          AppColors.statusExpired),
    ];
    return Row(children: List.generate(tiles.length, (i) {
      final t = tiles[i];
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i < tiles.length - 1 ? 10 : 0),
          child: ReusableCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(t.$3, color: t.$4, size: 22),
              const SizedBox(height: 8),
              Text(t.$2, style: AppTypography.headlineMedium.copyWith(color: t.$4)),
              Text(t.$1, style: AppTypography.labelMedium),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      ('Manage Users',     Icons.manage_accounts_outlined, AppColors.primary,       '/admin/users'),
      ('Audit Logs',       Icons.security_outlined,        AppColors.accent,        '/admin/audit-logs'),
      ('System Monitor',   Icons.monitor_heart_outlined,   AppColors.statusBooked,  '/admin/monitor'),
      ('System Settings',  Icons.settings_outlined,        AppColors.textSecondary, '/admin/settings'),
    ];
    return Column(children: actions.map((a) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReusableCard(
        onTap: () => context.push(a.$4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: a.$3.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Icon(a.$2, color: a.$3, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(a.$1, style: AppTypography.titleMedium)),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    )).toList());
  }

  Widget _buildTimetableActions(BuildContext context) {
    final actions = [
      ('Timetable Management', Icons.calendar_month,         AppColors.primary,      '/timetable/coordinator'),
      ('Validate Timetable',   Icons.fact_check_outlined,   AppColors.statusFree,   '/timetable/validate'),
      ('Publish Timetable',    Icons.publish_outlined,       AppColors.statusBooked, '/timetable/publish'),
      ('Venue Map',            Icons.map_outlined,           AppColors.accent,       '/venues/map'),
    ];
    return Column(children: actions.map((a) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReusableCard(
        onTap: () => context.push(a.$4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: a.$3.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Icon(a.$2, color: a.$3, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(a.$1, style: AppTypography.titleMedium)),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    )).toList());
  }

  void _showProfileSheet(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
