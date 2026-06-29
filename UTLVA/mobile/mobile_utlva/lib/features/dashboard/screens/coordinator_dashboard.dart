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
import '../../notifications/services/notification_service.dart';
import '../../timetable/models/emergency_session.dart';
import '../../timetable/services/timetable_service.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  int _currentIndex = 0;

  final _notifService = NotificationService();
  final _ttService = TimetableService();

  int _unreadCount = 0;
  List<EmergencySession> _pendingSessions = [];

  static const _navRoutes = [
    null,
    '/timetable/coordinator',
    '/venues/map',
    '/admin/users',
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
      final sessions = await _ttService.getEmergencySessions(status: 'PENDING');
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _pendingSessions = sessions;
        });
        // Show pending sessions popup if there are new requests
        if (sessions.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showPendingSessionsSheet();
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
        title: 'Coordinator Dashboard',
        actions: [
          // Notification bell with unread badge
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
          // Profile icon
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
        role: UserRole.coordinator,
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
          const SizedBox(height: 20),

          // Pending sessions alert banner
          if (_pendingSessions.isNotEmpty) ...[
            _buildPendingSessionsBanner(),
            const SizedBox(height: 16),
          ],

          _buildStatsRow(),
          const SizedBox(height: 16),

          // Publish Timetable
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

          // Auto-Generate
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

          // Validate
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

          // Timetable Management
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

          // Emergency Sessions with badge
          _buildEmergencyCard(),
          const SizedBox(height: 10),

          // Manage Users
          ReusableCard(
            onTap: () => context.push('/admin/users'),
            backgroundColor: AppColors.secondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.manage_accounts_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Manage Users', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Create and manage lecturers, students, and coordinators', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textOnPrimary),
            ]),
          ),
          const SizedBox(height: 10),

          // Bulk Enrollment (FR-52)
          ReusableCard(
            onTap: () => context.push('/admin/bulk-enroll'),
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.upload_file_outlined, color: AppColors.textOnPrimary, size: 26),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bulk Enrollment', style: AppTypography.titleMedium.copyWith(color: AppColors.textOnPrimary)),
                Text('Upload CSV to create students or lecturer accounts', style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary.withAlpha(200))),
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

  // ── Pending sessions banner ────────────────────────────────────────────────

  Widget _buildPendingSessionsBanner() {
    return GestureDetector(
      onTap: _showPendingSessionsSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.statusBooked.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.statusBooked.withAlpha(80)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.statusBooked, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${_pendingSessions.length} Emergency Session${_pendingSessions.length > 1 ? "s" : ""} Awaiting Review',
                style: AppTypography.titleMedium.copyWith(
                    color: AppColors.statusBooked, fontWeight: FontWeight.w700),
              ),
              Text('Tap to review requests from lecturers',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.statusBooked),
        ]),
      ),
    );
  }

  Widget _buildEmergencyCard() {
    return Stack(
      children: [
        ReusableCard(
          onTap: _showPendingSessionsSheet,
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
        if (_pendingSessions.isNotEmpty)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_pendingSessions.length}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  // ── Pending sessions bottom sheet with 4 action buttons ───────────────────

  void _showPendingSessionsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => _PendingSessionsSheet(
          sessions: _pendingSessions,
          ttService: _ttService,
          scrollController: scrollCtrl,
          onRefresh: () {
            Navigator.pop(ctx);
            _refreshBadges();
          },
          onViewTimetable: () {
            Navigator.pop(ctx);
            context.push('/timetable/coordinator');
          },
          onViewVenues: () {
            Navigator.pop(ctx);
            context.push('/venues/map');
          },
        ),
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final stats = [
      ('Venues', '13', Icons.location_city_outlined, AppColors.primary),
      ('Pending', '${_pendingSessions.length}', Icons.pending_actions_outlined, AppColors.statusBooked),
      ('Alerts', '$_unreadCount', Icons.notifications_active_outlined, AppColors.error),
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

  // ── Quick actions ──────────────────────────────────────────────────────────

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
              child: Text(header,
                  style: AppTypography.titleLarge.copyWith(color: color)),
            ),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReusableCard(
                    onTap: () => context.push(item.$3),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: color.withAlpha(20),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(item.$2, color: color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Text(item.$1, style: AppTypography.titleMedium)),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
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

// ── Pending sessions review sheet (coordinator) ───────────────────────────────

class _PendingSessionsSheet extends StatefulWidget {
  final List<EmergencySession> sessions;
  final TimetableService ttService;
  final ScrollController scrollController;
  final VoidCallback onRefresh;
  final VoidCallback onViewTimetable;
  final VoidCallback onViewVenues;

  const _PendingSessionsSheet({
    required this.sessions,
    required this.ttService,
    required this.scrollController,
    required this.onRefresh,
    required this.onViewTimetable,
    required this.onViewVenues,
  });

  @override
  State<_PendingSessionsSheet> createState() => _PendingSessionsSheetState();
}

class _PendingSessionsSheetState extends State<_PendingSessionsSheet> {
  final _noteCtrl = TextEditingController();
  int? _processingId;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve(EmergencySession session) async {
    await _showConfirmDialog(
      title: 'Confirm Approval',
      message:
          'Approve the emergency session for ${session.courseCode}?\n'
          'The requested venue will be set to BOOKED.',
      confirmLabel: 'Approve',
      confirmColor: AppColors.statusFree,
      onConfirm: (note) async {
        setState(() => _processingId = session.id);
        try {
          await widget.ttService.approveEmergencySession(session.id, note);
          widget.onRefresh();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
          }
        } finally {
          if (mounted) setState(() => _processingId = null);
        }
      },
    );
  }

  Future<void> _reject(EmergencySession session) async {
    await _showConfirmDialog(
      title: 'Reject Session',
      message: 'Reject the emergency session for ${session.courseCode}?\n'
          'The requesting lecturer will be notified.',
      confirmLabel: 'Reject',
      confirmColor: AppColors.error,
      onConfirm: (note) async {
        setState(() => _processingId = session.id);
        try {
          await widget.ttService.rejectEmergencySession(session.id, note);
          widget.onRefresh();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
          }
        } finally {
          if (mounted) setState(() => _processingId = null);
        }
      },
    );
  }

  Future<void> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function(String note) onConfirm,
  }) async {
    final noteCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, style: AppTypography.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Reason for your decision',
            ),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm(noteCtrl.text.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pending Requests',
                      style: AppTypography.headlineMedium),
                  Text('${widget.sessions.length} emergency session${widget.sessions.length > 1 ? "s" : ""} awaiting your review',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              // View Timetable button
              OutlinedButton.icon(
                onPressed: widget.onViewTimetable,
                icon: const Icon(Icons.calendar_month, size: 14),
                label: const Text('Timetable'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 6),
              // View Venues button
              OutlinedButton.icon(
                onPressed: widget.onViewVenues,
                icon: const Icon(Icons.map_outlined, size: 14),
                label: const Text('Venues'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: widget.sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) =>
                _SessionReviewCard(
                  session: widget.sessions[i],
                  isProcessing: _processingId == widget.sessions[i].id,
                  onApprove: () => _approve(widget.sessions[i]),
                  onReject: () => _reject(widget.sessions[i]),
                  onViewVenues: widget.onViewVenues,
                  onViewTimetable: widget.onViewTimetable,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Single session review card ─────────────────────────────────────────────────

class _SessionReviewCard extends StatelessWidget {
  final EmergencySession session;
  final bool isProcessing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewVenues;
  final VoidCallback onViewTimetable;

  const _SessionReviewCard({
    required this.session,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onViewVenues,
    required this.onViewTimetable,
  });

  @override
  Widget build(BuildContext context) {
    final hasConflict = session.hasConflicts;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: hasConflict
              ? AppColors.error.withAlpha(80)
              : AppColors.primary.withAlpha(40),
        ),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: hasConflict
                  ? AppColors.error.withAlpha(15)
                  : AppColors.primary.withAlpha(10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  session.title.isNotEmpty ? session.title : session.courseCode,
                  style: AppTypography.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasConflict)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withAlpha(80)),
                  ),
                  child: Text('CONFLICT',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.error, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Session info
                Text(session.courseName,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _row(Icons.person_outline, 'Lecturer: ${session.lecturerName}'),
                const SizedBox(height: 4),
                _row(Icons.calendar_today_outlined,
                    '${session.requestedDate}  ·  ${session.dayDisplay}  '
                    '${_fmt(session.startTime)}–${_fmt(session.endTime)}'),
                if (session.venueCode != null) ...[
                  const SizedBox(height: 4),
                  _row(Icons.place_outlined,
                      'Venue: ${session.venueCode} ${session.venueName ?? ""}'),
                ],
                const SizedBox(height: 4),
                _row(Icons.info_outline, session.reason, maxLines: 3),

                // Conflict flags
                if (hasConflict) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (session.lecturerConflict)
                      _conflictChip('Lecturer Conflict'),
                    if (session.venueConflict) _conflictChip('Venue Conflict'),
                    if (session.groupConflict) _conflictChip('Group Conflict'),
                    if (session.capacityConflict)
                      _conflictChip('Capacity Issue'),
                  ]),
                ],

                const SizedBox(height: 14),

                // ── 4 action buttons (SRS §3.7 NOTE point ii) ─────────────
                isProcessing
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary))
                    : Column(children: [
                        Row(children: [
                          // a. Confirm
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onApprove,
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Confirm'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.statusFree,
                                  padding: const EdgeInsets.symmetric(vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // b. Reject
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onReject,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Reject'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  padding: const EdgeInsets.symmetric(vertical: 10)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          // c. View Venues
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onViewVenues,
                              icon: const Icon(Icons.map_outlined, size: 15),
                              label: const Text('View Venues'),
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // d. View Timetable
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onViewTimetable,
                              icon: const Icon(Icons.calendar_month_outlined,
                                  size: 15),
                              label: const Text('View Timetable'),
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8)),
                            ),
                          ),
                        ]),
                      ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text, {int maxLines = 2}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style: AppTypography.bodySmall,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _conflictChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withAlpha(60)),
        ),
        child: Text(label,
            style: AppTypography.caption
                .copyWith(color: AppColors.error, fontSize: 10)),
      );

  String _fmt(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}
