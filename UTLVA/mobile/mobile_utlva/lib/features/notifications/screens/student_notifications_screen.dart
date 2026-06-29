import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../timetable/models/emergency_session.dart';
import '../../timetable/services/timetable_service.dart';

/// FR-41 — In-app notification centre for students.
///
/// Aggregates alerts from existing endpoints (no separate Notification model yet):
///   • Approved emergency sessions for the student's group
///   • (Future phases: session confirmations, postponements via push FCM)
///
/// The screen is intentionally read-only: tapping a session alert navigates
/// to the emergency sessions screen for full details.
class StudentNotificationsScreen extends StatefulWidget {
  const StudentNotificationsScreen({super.key});

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState
    extends State<StudentNotificationsScreen> {
  final _ttService = TimetableService();

  List<_NotificationItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // FR-41: Pull approved emergency sessions as notification items
      final sessions = await _ttService.getStudentEmergencySessions();
      final items = sessions.map((s) => _NotificationItem.fromEmergency(s)).toList();
      // Most recent first
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Notifications',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return _buildError();
    }
    if (_items.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => _NotificationTile(
          item: _items[i],
          onTap: () => context.push('/student/emergency-sessions'),
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.notifications_none_outlined, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('No notifications',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            'You will be notified here when lecturers confirm,\n'
            'postpone, or cancel sessions, or when emergency\n'
            'sessions are added for your group.',
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ]),
      );

  Widget _buildError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Could not load notifications', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      );
}

// ── Notification item model (in-screen only — not persisted) ──────────────────

class _NotificationItem {
  final _NotifType type;
  final String title;
  final String body;
  final String timestamp;
  final IconData icon;
  final Color color;

  const _NotificationItem({
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.icon,
    required this.color,
  });

  factory _NotificationItem.fromEmergency(EmergencySession s) {
    final course = s.title.isNotEmpty ? s.title : s.courseCode;
    final dateTime =
        '${s.requestedDate}  ·  ${s.dayDisplay}  '
        '${_fmtTime(s.startTime)} – ${_fmtTime(s.endTime)}';
    final venue = s.venueCode != null ? ' at ${s.venueCode}' : '';
    return _NotificationItem(
      type: _NotifType.emergency,
      title: 'Emergency Session: $course',
      body: '$dateTime$venue\nLecturer: ${s.lecturerName}',
      timestamp: s.createdAt,
      icon: Icons.warning_amber_rounded,
      color: AppColors.statusBooked,
    );
  }

  static String _fmtTime(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}

enum _NotifType { emergency }

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final _NotificationItem item;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.color.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, size: 20, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(item.body,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(item.timestamp),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _relativeTime(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTimestamp).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return isoTimestamp;
    }
  }
}

// ── Info banner shown in dashboard's notification section ─────────────────────

/// Compact notification preview for embedding in the student dashboard.
/// Shows the most recent item and a "See all" link.
class StudentNotificationsBanner extends StatefulWidget {
  const StudentNotificationsBanner({super.key});

  @override
  State<StudentNotificationsBanner> createState() =>
      _StudentNotificationsBannerState();
}

class _StudentNotificationsBannerState
    extends State<StudentNotificationsBanner> {
  final _ttService = TimetableService();
  List<EmergencySession> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await _ttService.getStudentEmergencySessions();
      if (mounted) {
        setState(() {
          _recent = sessions.take(3).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Fixed height so Center has bounded constraints inside the dashboard Column.
      // Center inside an unbounded Column (SingleChildScrollView child) causes
      // "Cannot hit test a render box with no size" which freezes the whole screen.
      return const SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          ),
        ),
      );
    }
    if (_recent.isEmpty) {
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
    return ReusableCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ..._recent.map((s) => _BannerTile(session: s)),
          InkWell(
            onTap: () => context.push('/notifications'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('See all notifications',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.primary)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerTile extends StatelessWidget {
  final EmergencySession session;
  const _BannerTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final course = session.title.isNotEmpty ? session.title : session.courseCode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.statusBooked),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emergency: $course',
                    style: AppTypography.labelMedium,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${session.dayDisplay}  ${_fmt(session.startTime)}–${_fmt(session.endTime)}'
                  '${session.venueCode != null ? "  ·  ${session.venueCode}" : ""}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}
