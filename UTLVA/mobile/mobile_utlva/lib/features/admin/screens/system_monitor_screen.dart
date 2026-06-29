import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../services/user_management_service.dart';

class SystemMonitorScreen extends StatefulWidget {
  const SystemMonitorScreen({super.key});
  @override
  State<SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<SystemMonitorScreen> {
  final _service = UserManagementService();
  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _service.getSystemStats();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'System Monitor',
        extraActions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _data == null
              ? Center(child: Text('No data.', style: AppTypography.bodyMedium))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _sectionTitle('Users'),
                      _buildUserStats(),
                      const SizedBox(height: 20),
                      _sectionTitle('Timetable'),
                      _buildTimetableStats(),
                      const SizedBox(height: 20),
                      _sectionTitle('Venues'),
                      _buildVenueStats(),
                      const SizedBox(height: 20),
                      _sectionTitle('Audit Activity'),
                      _buildAuditStats(),
                    ]),
                  ),
                ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: AppTypography.titleLarge),
  );

  Widget _buildUserStats() {
    final users = _data!['users'] as Map<String, dynamic>? ?? {};
    final byRole = users['by_role'] as Map<String, dynamic>? ?? {};
    final roleColors = {
      'SYSTEM_ADMIN': AppColors.error,
      'COORDINATOR': AppColors.accent,
      'LECTURER': AppColors.primary,
      'STUDENT': AppColors.statusBooked,
    };
    return ReusableCard(
      child: Column(children: [
        _statRow('Total Users', '${users['total'] ?? 0}', AppColors.primary),
        _divider(),
        _statRow('Active', '${users['active'] ?? 0}', AppColors.statusFree),
        _divider(),
        _statRow('Inactive', '${users['inactive'] ?? 0}', AppColors.statusExpired),
        _divider(),
        ...byRole.entries.map((e) => Column(children: [
          _statRow(e.key.replaceAll('_', ' '), '${e.value}', roleColors[e.key] ?? AppColors.textSecondary),
          if (e.key != byRole.keys.last) _divider(),
        ])),
      ]),
    );
  }

  Widget _buildTimetableStats() {
    final tt = _data!['timetable'] as Map<String, dynamic>? ?? {};
    return ReusableCard(
      child: Column(children: [
        _statRow('Total Entries', '${tt['total_entries'] ?? 0}', AppColors.primary),
        _divider(),
        _statRow('Published', '${tt['published'] ?? 0}', AppColors.statusFree),
      ]),
    );
  }

  Widget _buildVenueStats() {
    final v = _data!['venues'] as Map<String, dynamic>? ?? {};
    final byStatus = v['by_status'] as Map<String, dynamic>? ?? {};
    final statusColors = {
      'FREE': AppColors.statusFree,
      'BOOKED': AppColors.statusBooked,
      'IN_USE': AppColors.statusInUse,
      'EXPIRED': AppColors.statusExpired,
      'MAINTENANCE': AppColors.textSecondary,
    };
    return ReusableCard(
      child: Column(children: [
        _statRow('Total Venues', '${v['total'] ?? 0}', AppColors.primary),
        _divider(),
        _statRow('Active Venues', '${v['active'] ?? 0}', AppColors.statusFree),
        _divider(),
        ...byStatus.entries.map((e) => Column(children: [
          _statRow(e.key, '${e.value}', statusColors[e.key] ?? AppColors.textSecondary),
          if (e.key != byStatus.keys.last) _divider(),
        ])),
      ]),
    );
  }

  Widget _buildAuditStats() {
    final a = _data!['audit_log'] as Map<String, dynamic>? ?? {};
    final recent = (a['recent'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Column(children: [
      ReusableCard(
        child: Column(children: [
          _statRow('Total Log Entries', '${a['total'] ?? 0}', AppColors.accent),
          _divider(),
          _statRow("Today's Activity", '${a['today'] ?? 0}', AppColors.primary),
        ]),
      ),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Recent Actions', style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        ...recent.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ReusableCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.history_outlined, size: 16, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['action']}'.replaceAll('_', ' '),
                    style: AppTypography.labelMedium),
                Text('${e['user__full_name'] ?? 'System'}',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ])),
              Text(
                '${e['timestamp']}'.substring(0, 16).replaceFirst('T', ' '),
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
            ]),
          ),
        )),
      ],
    ]);
  }

  Widget _statRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(child: Text(label, style: AppTypography.bodyMedium)),
      Text(value, style: AppTypography.headlineMedium.copyWith(color: color, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);
}
