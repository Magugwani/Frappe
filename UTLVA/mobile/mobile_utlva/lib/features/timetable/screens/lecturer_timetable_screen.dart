import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../services/confirmation_retry_service.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../core/widgets/timetable_grid_view.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_entry.dart';
import '../models/emergency_session.dart';
import '../services/timetable_service.dart';

class LecturerTimetableScreen extends StatefulWidget {
  /// When opened from a reminder email deep-link, these pre-trigger the action.
  /// [autoActionEntryId] — the timetable entry to act on (0 = none)
  /// [autoAction]        — 'confirm' | 'postpone' | 'cancel'
  final int autoActionEntryId;
  final String autoAction;

  const LecturerTimetableScreen({
    super.key,
    this.autoActionEntryId = 0,
    this.autoAction = '',
  });
  @override
  State<LecturerTimetableScreen> createState() => _LecturerTimetableScreenState();
}

class _LecturerTimetableScreenState extends State<LecturerTimetableScreen>
    with SingleTickerProviderStateMixin {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  late final TabController _tabController;

  List<TimetableEntry> _entries = [];
  List<LecturerCourse> _courses = [];
  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  AcademicYear? _selectedYear;
  Semester? _selectedSemester;
  bool _loading = true;

  // FR-33/FR-35: per-entry confirmation status for today's sessions
  final Map<int, Map<String, dynamic>> _confirmationStatus = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData().then((_) {
      // SRS §3.11: if opened from a reminder email deep-link, auto-trigger action
      if (widget.autoActionEntryId > 0 && widget.autoAction.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleAutoAction());
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Load confirmation status for today's entries (FR-33/FR-35).
  Future<void> _loadConfirmationStatuses(List<TimetableEntry> entries) async {
    final today = DateTime.now();
    final dayName = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][today.weekday - 1];
    final todayEntries = entries.where((e) => e.dayOfWeek == dayName).toList();
    for (final entry in todayEntries) {
      try {
        final s = await _ttService.getConfirmationStatus(entry.id);
        if (mounted) setState(() => _confirmationStatus[entry.id] = s);
      } catch (_) {}
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final refs = await Future.wait([
        _acService.getYears(),
        _acService.getSemesters(),
        _ttService.getLecturerCourses().catchError((_) => <dynamic>[]),
      ]);
      _years    = refs[0] as List<AcademicYear>;
      _semesters= refs[1] as List<Semester>;
      final rawCourses = List<Map<String,dynamic>>.from(refs[2] as Iterable);
      if (mounted) setState(() {
        if (_years.isNotEmpty) _selectedYear = _years.first;
        if (_semesters.isNotEmpty) _selectedSemester = _semesters.first;
        _courses = rawCourses.map(LecturerCourse.fromJson).toList();
      });
      await _loadEntries();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final entries = await _ttService.getLecturerTimetable(
        academicYearId: _selectedYear?.id,
        semesterId: _selectedSemester?.id,
      );
      if (mounted) {
        setState(() => _entries = entries);
        // Load confirmation statuses for today's sessions (FR-33/FR-35)
        _loadConfirmationStatuses(entries);
      }
    } catch (_) {
      if (mounted) setState(() => _entries = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'My Timetable',
        showBackButton: true,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar: Timetable | My Courses (FR-20)
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(text: 'Schedule', icon: Icon(Icons.calendar_month_outlined, size: 18)),
              Tab(text: 'My Courses (${_courses.length})', icon: const Icon(Icons.menu_book_outlined, size: 18)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTimetableTab(),
                _buildCoursesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableTab() {
    return Column(
      children: [
          // Filter bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _chip(_selectedYear?.name ?? 'All Years', Icons.calendar_today_outlined, AppColors.statusBooked,
                    () => _showPicker<AcademicYear>('Academic Year', _years, _selectedYear, (y) { setState(() => _selectedYear = y); _loadEntries(); }, (y) => y.name)),
                _chip(_selectedSemester?.name ?? 'All Semesters', Icons.date_range_outlined, AppColors.statusBooked,
                    () => _showPicker<Semester>('Semester', _semesters, _selectedSemester, (s) { setState(() => _selectedSemester = s); _loadEntries(); }, (s) => s.name)),
                TextButton.icon(icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh'), onPressed: _loadEntries),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.statusBooked))
                : _entries.isEmpty
                    ? _buildEmpty()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTodayStatusPanel(),
                            _buildSummary(),
                            const SizedBox(height: 14),
                            TimetableGridView(
                              entries: _entries,
                              onEntryTap: (e) => _showSessionActions(e),
                            ),
                            const SizedBox(height: 12),
                            _buildSessionList(),
                          ],
                        ),
                      ),
          ),
        ],
    );  // end _buildTimetableTab Column
  }

  // ── My Courses tab (FR-20) ────────────────────────────────────────────────

  Widget _buildCoursesTab() {
    if (_courses.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book_outlined, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('No courses assigned yet', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text('Contact the Timetable Coordinator to assign courses.', style: AppTypography.bodySmall, textAlign: TextAlign.center),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = _courses[i];
        return ReusableCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(c.courseCode, style: AppTypography.labelLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(c.courseName, style: AppTypography.titleMedium, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              _courseChip(Icons.school_outlined, '${c.programmeCode} Y${c.yearOfStudy}', AppColors.accent),
              _courseChip(Icons.schedule_outlined, '${c.weeklyHours}h/week', AppColors.statusBooked),
              _courseChip(Icons.meeting_room_outlined, c.requiredVenueType.replaceAll('_', ' '), AppColors.textSecondary),
              if (c.academicYear != null) _courseChip(Icons.calendar_today_outlined, c.academicYear!, AppColors.statusFree),
            ]),
          ]),
        );
      },
    );
  }

  Widget _courseChip(IconData icon, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: AppTypography.caption.copyWith(color: color)),
    ],
  );

  Widget _chip(String label, IconData icon, Color color, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
      onPressed: onTap,
      backgroundColor: color.withAlpha(15),
      side: BorderSide(color: color.withAlpha(60)),
    );
  }

  // ── FR-33/FR-35: Today's session status panel ─────────────────────────────

  Widget _buildTodayStatusPanel() {
    final today = DateTime.now();
    final dayName = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][today.weekday - 1];
    final todayEntries = _entries.where((e) => e.dayOfWeek == dayName).toList();
    if (todayEntries.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          const Icon(Icons.today_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Text("Today's Sessions", style: AppTypography.titleMedium.copyWith(color: AppColors.accent)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 12),
            label: const Text('Refresh', style: TextStyle(fontSize: 11)),
            onPressed: () => _loadConfirmationStatuses(todayEntries),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.accent),
          ),
        ]),
      ),
      ...todayEntries.map((e) {
        final cs = _confirmationStatus[e.id];
        final sessionStatus = cs?['status'] as String? ?? 'PENDING';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ReusableCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _statusDot(sessionStatus),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e.courseCode} — ${e.startHHMM}–${e.endHHMM}',
                    style: AppTypography.labelLarge),
                if (e.venueCode != null)
                  Text('${e.venueCode}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                Text(_statusLabel(sessionStatus, cs),
                    style: AppTypography.caption.copyWith(color: _statusColor(sessionStatus), fontWeight: FontWeight.w600)),
              ])),
              TextButton(
                onPressed: () => _showSessionActions(e),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary, visualDensity: VisualDensity.compact),
                child: const Text('Actions'),
              ),
            ]),
          ),
        );
      }),
      const Divider(height: 20),
    ]);
  }

  Widget _statusDot(String status) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle),
  );

  Color _statusColor(String status) => switch (status) {
    'CONFIRMED' => AppColors.statusFree,
    'EXPIRED'   => AppColors.statusExpired,
    'CANCELLED' => AppColors.textSecondary,
    _           => AppColors.statusBooked,  // PENDING
  };

  String _statusLabel(String status, Map<String, dynamic>? cs) {
    return switch (status) {
      'CONFIRMED' => 'Confirmed at ${(cs?['confirmed_at'] as String?)?.substring(11, 16) ?? ''}',
      'EXPIRED'   => 'Expired — confirmation window closed',
      'CANCELLED' => 'Cancelled',
      _           => 'Pending — tap Actions to confirm',
    };
  }

  Widget _buildSummary() {
    final days = _entries.map((e) => e.dayOfWeek).toSet().length;
    return Row(children: [
      const Icon(Icons.schedule, size: 16, color: AppColors.primary),
      const SizedBox(width: 6),
      Text('${_entries.length} sessions across $days days', style: AppTypography.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
    ]);
  }

  // ── Session confirm / end ─────────────────────────────────────────────────

  Future<void> _showSessionActions(TimetableEntry entry) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entry.courseCode} — ${entry.courseName}', style: AppTypography.headlineMedium),
          Text('${entry.dayOfWeek} ${entry.startHHMM}–${entry.endHHMM}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          if (entry.venueCode != null) Text('Venue: ${entry.venueCode}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.accent)),
          const SizedBox(height: 20),
          // Confirm session button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Confirm Session (Start)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusFree,
                foregroundColor: AppColors.textOnPrimary,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _doConfirm(entry);
              },
            ),
          ),
          const SizedBox(height: 10),
          // Postpone session button (FR-26/27)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.update_outlined, color: AppColors.statusBooked),
              label: const Text('Postpone Session', style: TextStyle(color: AppColors.statusBooked)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.statusBooked),
                minimumSize: const Size(0, 48),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _showPostponeDialog(entry);
              },
            ),
          ),
          const SizedBox(height: 10),
          // End session button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined, color: AppColors.statusInUse),
              label: const Text('End Session', style: TextStyle(color: AppColors.statusInUse)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.statusInUse),
                minimumSize: const Size(0, 48),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _doEnd(entry);
              },
            ),
          ),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss'))),
        ]),
      ),
    );
  }

  Future<void> _doConfirm(TimetableEntry entry) async {
    final retryService = ConfirmationRetryService();
    final sessionDate  = DateTime.now();
    final dateStr = '${sessionDate.year}-'
        '${sessionDate.month.toString().padLeft(2, '0')}-'
        '${sessionDate.day.toString().padLeft(2, '0')}';

    try {
      final r = await _ttService.confirmSession(entry.id);

      if (!mounted) return;

      final errorCode = r['error_code'] as String?;

      // SRS §3.12: CONFLICT — another device already confirmed
      if (errorCode == 'CONFLICT') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Session already confirmed on another device.'),
          backgroundColor: AppColors.statusBooked,
        ));
        _loadEntries();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['message'] ?? 'Session confirmed.'),
        backgroundColor: r['success'] == true ? AppColors.statusFree : AppColors.error,
      ));
      _loadEntries();
    } catch (e) {
      // SRS §3.12: Network loss — queue for retry every 30 s for up to 30 min
      if (!mounted) return;
      await retryService.scheduleRetry(entry.id, dateStr);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'No network — confirmation queued. It will retry automatically '
              'every 30 seconds for up to 30 minutes.'),
          backgroundColor: AppColors.statusBooked,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: AppColors.textOnPrimary,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _doCancel(TimetableEntry entry, {bool urgent = false}) async {
    try {
      final r = await _ttService.cancelSession(entry.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['message'] ?? 'Session cancelled. Students notified.'),
        backgroundColor: r['success'] == true ? AppColors.statusExpired : AppColors.error,
      ));
      _loadEntries();
      // SRS §3.12: after cancelling an in-progress session, offer alternative
      if (r['success'] == true && urgent) _offerAlternativeSession(entry);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _doEnd(TimetableEntry entry) async {
    try {
      final r = await _ttService.endSession(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? 'Session ended.'),
          backgroundColor: r['success'] == true ? AppColors.statusBooked : AppColors.error,
        ));
        _loadEntries();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  // ── Postpone dialog (FR-26, FR-27) ───────────────────────────────────────

  Future<void> _showPostponeDialog(TimetableEntry entry) async {
    DateTime? newDate;
    String newDay = entry.dayOfWeek;
    String newStart = entry.startTime;
    String newEnd   = entry.endTime;
    final reasonCtrl = TextEditingController();

    const days = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'];
    const times = ['07:00:00','08:00:00','09:00:00','10:00:00','11:00:00','12:00:00',
                   '13:00:00','14:00:00','15:00:00','16:00:00','17:00:00','18:00:00','19:00:00'];
    String _hm(String t) { final p=t.split(':'); return '${p[0]}:${p[1]}'; }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Postpone — ${entry.courseCode}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(newDate == null ? 'Pick New Date *' : '${newDate!.day}/${newDate!.month}/${newDate!.year}'),
              leading: const Icon(Icons.calendar_today_outlined, color: AppColors.primary),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setS(() { newDate = d; newDay = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][d.weekday - 1]; });
              },
            ),
            DropdownButtonFormField<String>(
              value: newDay,
              decoration: const InputDecoration(labelText: 'Day'),
              items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setS(() => newDay = v!),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: newStart,
                decoration: const InputDecoration(labelText: 'Start', isDense: true),
                items: times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
                onChanged: (v) => setS(() => newStart = v!),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                value: newEnd,
                decoration: const InputDecoration(labelText: 'End', isDense: true),
                items: times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
                onChanged: (v) => setS(() => newEnd = v!),
              )),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason *', hintText: 'Why is this being postponed?'),
              maxLines: 2,
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (newDate == null || reasonCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Postpone'),
            ),
          ],
        ),
      ),
    );

    if (result != true || newDate == null) return;
    try {
      final r = await _ttService.postponeSession(
        entryId: entry.id,
        newDate: '${newDate!.year}-${newDate!.month.toString().padLeft(2,'0')}-${newDate!.day.toString().padLeft(2,'0')}',
        newDayOfWeek: newDay,
        newStartTime: newStart,
        newEndTime: newEnd,
        reason: reasonCtrl.text.trim(),
      );

      if (!mounted) return;

      // SRS §3.12: Session already in progress — cannot postpone
      if (r['error_code'] == 'SESSION_ALREADY_STARTED') {
        _showSessionAlreadyStartedDialog(entry);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['message'] ?? 'Session postponed. Students notified.'),
        backgroundColor: r['success'] == true ? AppColors.statusBooked : AppColors.error,
      ));
      _loadEntries();
      // After postpone, offer to create an alternative session (SRS §3.11 + §3.12)
      if (r['success'] == true) _offerAlternativeSession(entry);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  /// SRS §3.12: SESSION_ALREADY_STARTED — session is IN_USE, cannot postpone.
  /// Offer: (a) Cancel the remainder of the session, or (b) Create Alternative.
  void _showSessionAlreadyStartedDialog(TimetableEntry entry) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.statusBooked),
          const SizedBox(width: 8),
          const Expanded(child: Text('Session Already Started')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'The session for ${entry.courseCode} is already IN PROGRESS — '
            'the venue is currently IN_USE and cannot be postponed.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.statusInUse.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.statusInUse.withAlpha(40)),
            ),
            child: Text(
              'You may cancel the REMAINDER of the session (venue will be released '
              'and students will be notified urgently), or create an alternative '
              'session for the content you could not cover.',
              style: AppTypography.caption.copyWith(color: AppColors.statusInUse),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/sessions/emergency');
            },
            icon: const Icon(Icons.add_alert_outlined, size: 15),
            label: const Text('Create Alternative'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _doCancel(entry, urgent: true);
            },
            icon: const Icon(Icons.stop_circle_outlined, size: 15),
            label: const Text('Cancel Remainder'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          ),
        ],
      ),
    );
  }

  /// SRS §3.11: After postponing, offer the lecturer to create an emergency
  /// (alternative) session so students still have a makeup class option.
  void _offerAlternativeSession(TimetableEntry entry) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.event_available, color: AppColors.accent),
          const SizedBox(width: 8),
          const Expanded(child: Text('Create Alternative Session?')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'The postponed session for ${entry.courseCode} has been recorded '
            'and students have been notified.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withAlpha(40)),
            ),
            child: Text(
              'Would you like to create an emergency / alternative session '
              'so students still have a makeup class?',
              style: AppTypography.bodySmall,
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, done'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/sessions/emergency');
            },
            icon: const Icon(Icons.add_alert_outlined, size: 16),
            label: const Text('Create Alternative Session'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }

  /// SRS §3.11: Handle action from reminder email deep-link.
  Future<void> _handleAutoAction() async {
    final entryId = widget.autoActionEntryId;
    final action  = widget.autoAction;
    if (entryId == 0 || action.isEmpty || !mounted) return;

    final entry = _entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session not found. It may have been updated.'),
          backgroundColor: AppColors.statusBooked,
        ),
      );
      return;
    }

    switch (action) {
      case 'confirm':
        await _doConfirm(entry);
      case 'postpone':
        await _showPostponeDialog(entry);
      case 'cancel':
        _showSessionActions(entry); // shows the full sheet including cancel
    }
  }

  Widget _buildSessionList() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tap any session in the grid to confirm, postpone, or end it.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
    ]);
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.event_busy, size: 56, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text('No sessions assigned yet', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Text('Contact the Timetable Coordinator.', style: AppTypography.bodySmall),
    ]),
  );

  void _showPicker<T>(String title, List<T> items, T? selected, ValueChanged<T> onSelect, String Function(T) label) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.headlineMedium),
          const SizedBox(height: 16),
          ...items.map((item) => ListTile(
            title: Text(label(item)),
            trailing: item == selected ? const Icon(Icons.check, color: AppColors.primary) : null,
            onTap: () { Navigator.pop(ctx); onSelect(item); },
          )),
        ]),
      ),
    );
  }
}
