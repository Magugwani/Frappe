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
import '../../notifications/models/app_notification.dart';
import '../../notifications/services/notification_service.dart';

class LecturerDashboard extends StatefulWidget {
  const LecturerDashboard({super.key});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  int _currentIndex = 0;

  final _notifService = NotificationService();
  int _unreadCount = 0;
  List<AppNotification> _approvalNotifs = [];

  static const _navRoutes = [
    null,
    '/timetable/lecturer',
    '/sessions/emergency',
    '/venues/map',
    '/notifications',
    null,
  ];

  @override
  void initState() {
    super.initState();
    _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    try {
      final count = await _notifService.getUnreadCount();
      final notifs = await _notifService.getNotifications();
      final approvals = notifs
          .where((n) => n.isEmergencyApproved && !n.isRead)
          .toList();
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _approvalNotifs = approvals;
        });
        // Show approval popup for first unread approval
        if (approvals.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showApprovalPopup(approvals.first);
          });
        }
      }
    } catch (_) {}
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    if (index == 5) {
      _showProfileSheet(context);
      setState(() => _currentIndex = 0);
      return;
    }
    if (index == 0) return;
    final route = _navRoutes[index]!;
    context.push(route).then((_) {
      if (mounted) {
        setState(() => _currentIndex = 0);
        _refreshBadges();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Lecturer Dashboard',
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: AppColors.textOnPrimary),
                onPressed: () => context
                    .push('/notifications')
                    .then((_) => _refreshBadges()),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined,
                color: AppColors.textOnPrimary),
            onPressed: () => _showProfileSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshBadges,
        child: _buildBody(user?.fullName ?? ''),
      ),
      bottomNavigationBar: CustomBottomNavigation(
        role: UserRole.lecturer,
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildBody(String name) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good day,',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
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
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),

          // Approval alerts banner
          if (_approvalNotifs.isNotEmpty) ...[
            _buildApprovalBanner(),
            const SizedBox(height: 14),
          ],

          _buildTodayCard(),
          const SizedBox(height: 16),

          // My Sessions
          ReusableCard(
            onTap: () => context.push('/timetable/lecturer'),
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Sessions', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Confirm or end your teaching sessions', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),

          // Official Timetable
          ReusableCard(
            onTap: () => context.push('/timetable/official'),
            backgroundColor: AppColors.secondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.grid_on_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Official Timetable', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Full university timetable — filter by programme', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),

          // Live Timetable
          ReusableCard(
            onTap: () => context.push('/timetable/live'),
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.sensors_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Live Venue Status', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Real-time availability · navigate to venues', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.navigation_outlined, size: 18, color: AppColors.textOnPrimary),
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

  // ── Approval banner ────────────────────────────────────────────────────────

  Widget _buildApprovalBanner() {
    return GestureDetector(
      onTap: () => _showApprovalPopup(_approvalNotifs.first),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.statusFree.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.statusFree.withAlpha(80)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.statusFree, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${_approvalNotifs.length} Emergency Session${_approvalNotifs.length > 1 ? "s" : ""} Approved!',
                style: AppTypography.titleMedium.copyWith(
                    color: AppColors.statusFree, fontWeight: FontWeight.w700),
              ),
              Text('Tap to notify your students',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.statusFree),
        ]),
      ),
    );
  }

  // ── Approval popup dialog ─────────────────────────────────────────────────

  void _showApprovalPopup(AppNotification notif) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LecturerApprovalDialog(
        notif: notif,
        service: _notifService,
        onDone: _refreshBadges,
      ),
    );
  }

  // ── Today card ─────────────────────────────────────────────────────────────

  Widget _buildTodayCard() {
    return ReusableCard(
      backgroundColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.calendar_today, color: AppColors.textOnPrimary, size: 18),
            const SizedBox(width: 8),
            Text("Today's Sessions",
                style: AppTypography.titleMedium
                    .copyWith(color: AppColors.textOnPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/timetable/lecturer'),
              child: Text('View all',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Open My Sessions to see today\'s schedule',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textOnPrimary.withAlpha(180)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final actions = [
      ('View Timetable', Icons.calendar_month_outlined, AppColors.primary,
          '/timetable/lecturer'),
      ('Create Emergency Session', Icons.add_alert_outlined,
          AppColors.statusExpired, '/sessions/emergency'),
      ('Find a Venue', Icons.search_outlined, AppColors.accent, '/venues/list'),
      ('Venue Map', Icons.map_outlined, AppColors.statusFree, '/venues/map'),
    ];
    return Column(
      children: actions.map((a) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ReusableCard(
            onTap: () => context.push(a.$4),
            child: Row(children: [
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
            ]),
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

// ── Lecturer approval dialog — "Send / Don't Send" ────────────────────────────

class _LecturerApprovalDialog extends StatefulWidget {
  final AppNotification notif;
  final NotificationService service;
  final VoidCallback onDone;

  const _LecturerApprovalDialog({
    required this.notif,
    required this.service,
    required this.onDone,
  });

  @override
  State<_LecturerApprovalDialog> createState() =>
      _LecturerApprovalDialogState();
}

class _LecturerApprovalDialogState extends State<_LecturerApprovalDialog> {
  bool _sending = false;
  String? _result;

  Future<void> _sendNotifications() async {
    final sessionId = widget.notif.relatedId;
    if (sessionId == null) {
      Navigator.pop(context);
      widget.onDone();
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await widget.service.notifyStudents(sessionId);
      final count = res['students_notified'] ?? 0;
      // Mark notification read
      await widget.service.markRead(widget.notif.id);
      if (mounted) {
        setState(() {
          _sending = false;
          _result = 'Successfully notified $count student${count != 1 ? "s" : ""}!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _result = 'Failed to notify: $e';
        });
      }
    }
  }

  Future<void> _skip() async {
    await widget.service.markRead(widget.notif.id);
    if (mounted) {
      Navigator.pop(context);
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return AlertDialog(
        title: Row(children: [
          Icon(
            _result!.startsWith('Failed')
                ? Icons.error_outline
                : Icons.check_circle_outline,
            color: _result!.startsWith('Failed')
                ? AppColors.error
                : AppColors.statusFree,
          ),
          const SizedBox(width: 8),
          const Text('Done'),
        ]),
        content: Text(_result!),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDone();
            },
            child: const Text('Close'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.check_circle_outline, color: AppColors.statusFree),
        const SizedBox(width: 8),
        const Expanded(child: Text('Emergency Session Confirmed!')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.notif.body,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notify your students?',
                    style: AppTypography.titleMedium.copyWith(color: AppColors.textMain)),
                const SizedBox(height: 4),
                Text(
                  'Choosing "Send" will deliver in-app and email notifications '
                  'to all enrolled students about this emergency session.',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // "OK — Don't Send Notification"
        TextButton(
          onPressed: _sending ? null : _skip,
          child: const Text("OK — Don't Send"),
        ),
        // "OK — Send Notification"
        ElevatedButton.icon(
          onPressed: _sending ? null : _sendNotifications,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: AppColors.textOnPrimary, strokeWidth: 2))
              : const Icon(Icons.send_outlined, size: 16),
          label: const Text('OK — Send Notification'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
