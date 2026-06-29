import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/audit_log.dart';
import '../services/user_management_service.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _service = UserManagementService();
  List<AuditLogEntry> _logs = [];
  bool _loading = false;
  String? _actionFilter;

  // Distinct action types the admin can filter by
  static const _actionOptions = [
    ('All Actions', null),
    ('Login', 'LOGIN'),
    ('Logout', 'LOGOUT'),
    ('Create User', 'CREATE_USER'),
    ('Update User', 'UPDATE_USER'),
    ('Deactivate User', 'DEACTIVATE_USER'),
    ('Activate User', 'ACTIVATE_USER'),
    ('Bulk Create', 'BULK_CREATE_USER'),
    ('Password Changed', 'PASSWORD_UPDATED'),
    ('Venue Transition', 'VENUE_TRANSITION'),
    ('Venue Deactivated', 'VENUE_DEACTIVATED'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final logs = await _service.getAuditLogs(action: _actionFilter);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _actionColor(String action) => switch (action) {
        'LOGIN' || 'LOGOUT' => AppColors.statusBooked,
        'CREATE_USER' || 'ACTIVATE_USER' || 'BULK_CREATE_USER' => AppColors.statusFree,
        'DEACTIVATE_USER' || 'VENUE_DEACTIVATED' => AppColors.statusExpired,
        'UPDATE_USER' || 'PASSWORD_UPDATED' || 'VENUE_TRANSITION' => AppColors.accent,
        _ => AppColors.textSecondary,
      };

  IconData _actionIcon(String action) => switch (action) {
        'LOGIN' => Icons.login_outlined,
        'LOGOUT' => Icons.logout_outlined,
        'CREATE_USER' || 'BULK_CREATE_USER' => Icons.person_add_outlined,
        'UPDATE_USER' => Icons.edit_outlined,
        'DEACTIVATE_USER' => Icons.block_outlined,
        'ACTIVATE_USER' => Icons.check_circle_outline,
        'PASSWORD_UPDATED' => Icons.lock_reset_outlined,
        'VENUE_TRANSITION' => Icons.swap_horiz_outlined,
        'VENUE_DEACTIVATED' => Icons.meeting_room_outlined,
        _ => Icons.history_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Audit Logs',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(children: [
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _actionOptions.map((opt) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(opt.$1, style: AppTypography.caption.copyWith(
              color: _actionFilter == opt.$2 ? AppColors.primary : AppColors.textSecondary,
              fontWeight: _actionFilter == opt.$2 ? FontWeight.w700 : FontWeight.normal,
            )),
            selected: _actionFilter == opt.$2,
            onSelected: (_) { setState(() => _actionFilter = opt.$2); _load(); },
            selectedColor: AppColors.primary.withAlpha(20),
            side: BorderSide(color: _actionFilter == opt.$2 ? AppColors.primary : AppColors.divider),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        )).toList()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_logs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.history_outlined, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('No audit entries found', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _AuditCard(entry: _logs[i], color: _actionColor(_logs[i].action), icon: _actionIcon(_logs[i].action)),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final AuditLogEntry entry;
  final Color color;
  final IconData icon;
  const _AuditCard({required this.entry, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(entry.actionLabel,
                  style: AppTypography.labelLarge.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
            Text(entry.formattedTime, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 2),
          Text(entry.userName, style: AppTypography.bodySmall),
          if (entry.entityType.isNotEmpty)
            Text('${entry.entityType} #${entry.entityId}',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          if (entry.ipAddress != null)
            Text('IP: ${entry.ipAddress}',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ])),
      ]),
    );
  }
}
