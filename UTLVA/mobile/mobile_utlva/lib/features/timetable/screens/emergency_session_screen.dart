import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/emergency_session.dart';
import '../services/timetable_service.dart';

class EmergencySessionScreen extends StatefulWidget {
  const EmergencySessionScreen({super.key});

  @override
  State<EmergencySessionScreen> createState() => _EmergencySessionScreenState();
}

class _EmergencySessionScreenState extends State<EmergencySessionScreen>
    with SingleTickerProviderStateMixin {
  final _service = TimetableService();
  late TabController _tabController;

  List<EmergencySession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sessions = await _service.getEmergencySessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role ?? '';
    final isCoordinator = role == 'COORDINATOR' || role == 'SYSTEM_ADMIN';

    final mySessions = _sessions.where((s) => s.requestedByName != null).toList();
    final allSessions = _sessions;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Emergency Sessions', showBackButton: true),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.error,
        icon: const Icon(Icons.emergency_outlined, color: AppColors.textOnPrimary),
        label: const Text('New Request', style: TextStyle(color: AppColors.textOnPrimary)),
        onPressed: () => _showCreateForm(context),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'My Requests'),
              Tab(text: 'All Sessions'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSessionList(mySessions, isCoordinator),
                          _buildSessionList(allSessions, isCoordinator),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
      const SizedBox(height: 12),
      Text('Failed to load sessions', style: AppTypography.titleMedium),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _loadSessions, child: const Text('Retry')),
    ]),
  );

  Widget _buildSessionList(List<EmergencySession> sessions, bool isCoordinator) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_busy_outlined, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No emergency sessions', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sessions.length,
        itemBuilder: (context, i) => _SessionCard(
          session: sessions[i],
          isCoordinator: isCoordinator,
          onReview: _loadSessions,
          service: _service,
        ),
      ),
    );
  }

  Future<void> _showCreateForm(BuildContext context) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CreateSessionForm(service: _service),
    );
    if (created == true && mounted) {
      _loadSessions();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Emergency session requested.'),
        backgroundColor: AppColors.statusFree,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ── Session Card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final EmergencySession session;
  final bool isCoordinator;
  final VoidCallback onReview;
  final TimetableService service;

  const _SessionCard({
    required this.session,
    required this.isCoordinator,
    required this.onReview,
    required this.service,
  });

  Color get _statusColor {
    switch (session.status) {
      case 'APPROVED': return AppColors.statusFree;
      case 'REJECTED': return AppColors.error;
      case 'CANCELLED': return AppColors.textSecondary;
      default: return AppColors.statusInUse;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Expanded(
              child: Text(
                '${session.courseCode} — ${session.courseName}',
                style: AppTypography.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _StatusBadge(label: session.statusDisplay, color: _statusColor),
          ]),
          const SizedBox(height: 6),
          Text(session.lecturerName, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${session.requestedDate} (${session.dayDisplay})', style: AppTypography.bodySmall),
            const SizedBox(width: 12),
            const Icon(Icons.access_time_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${_hm(session.startTime)} – ${_hm(session.endTime)}', style: AppTypography.bodySmall),
          ]),
          if (session.venueCode != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(session.venueCode!, style: AppTypography.bodySmall),
            ]),
          ],
          // Conflict warnings
          if (session.hasConflicts) ...[
            const SizedBox(height: 8),
            _buildConflictWarnings(),
          ],
          // Coordinator actions
          if (isCoordinator && session.status == 'PENDING') ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                onPressed: () => _showReviewDialog(context, approve: false),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusFree),
                onPressed: () => _showReviewDialog(context, approve: true),
                child: const Text('Approve', style: TextStyle(color: AppColors.textOnPrimary)),
              ),
            ]),
          ],
          // Review note
          if (session.reviewNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Review note: ${session.reviewNote}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildConflictWarnings() {
    final warnings = <String>[];
    if (session.lecturerConflict) warnings.add('Lecturer conflict');
    if (session.venueConflict) warnings.add('Venue conflict');
    if (session.groupConflict) warnings.add('Student group conflict');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(60)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(warnings.join(', '),
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning)),
        ),
      ]),
    );
  }

  String _hm(String t) {
    final parts = t.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  Future<void> _showReviewDialog(BuildContext context, {required bool approve}) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve Session' : 'Reject Session'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(approve
              ? 'Add an optional note for this approval:'
              : 'Please provide a reason for rejection:'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Note (optional)...'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: approve ? AppColors.statusFree : AppColors.error),
            child: Text(approve ? 'Approve' : 'Reject',
                style: const TextStyle(color: AppColors.textOnPrimary)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        if (approve) {
          await service.approveEmergencySession(session.id, controller.text);
        } else {
          await service.rejectEmergencySession(session.id, controller.text);
        }
        onReview();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    }
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
    );
  }
}

// ── Create Emergency Session Form ─────────────────────────────────────────────

class _CreateSessionForm extends StatefulWidget {
  final TimetableService service;
  const _CreateSessionForm({required this.service});

  @override
  State<_CreateSessionForm> createState() => _CreateSessionFormState();
}

class _CreateSessionFormState extends State<_CreateSessionForm> {
  final _acService = AcademicsService();
  final _reasonController = TextEditingController();

  List<Course> _courses = [];
  List<Lecturer> _lecturers = [];
  bool _loading = true;
  bool _saving = false;

  int? _courseId;
  int? _lecturerId;
  DateTime? _requestedDate;
  String _day = 'MONDAY';
  String _startTime = '08:00:00';
  String _endTime = '10:00:00';

  static const _days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
  static const _times = [
    '07:00:00', '08:00:00', '09:00:00', '10:00:00', '11:00:00', '12:00:00',
    '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00', '18:00:00',
  ];

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    try {
      final results = await Future.wait([
        _acService.getCourses(),
        _acService.getLecturers(),
      ]);
      if (mounted) {
        setState(() {
          _courses = results[0] as List<Course>;
          _lecturers = results[1] as List<Lecturer>;
          if (_courses.isNotEmpty) _courseId = _courses.first.id;
          if (_lecturers.isNotEmpty) _lecturerId = _lecturers.first.id;
        });
      }
    } catch (_) {
      // silently ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _requestedDate = picked);
    }
  }

  String _hm(String t) {
    final parts = t.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  Future<void> _submit() async {
    if (_courseId == null || _lecturerId == null || _requestedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fill all required fields.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reason is required.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.createEmergencySession(
        courseId: _courseId!,
        lecturerId: _lecturerId!,
        requestedDate: _requestedDate!.toIso8601String().split('T').first,
        dayOfWeek: _day,
        startTime: _startTime,
        endTime: _endTime,
        reason: _reasonController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Request Emergency Session', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),

        if (_loading)
          const Center(child: CircularProgressIndicator(color: AppColors.primary))
        else ...[
          // Course
          DropdownButtonFormField<int>(
            value: _courseId,
            decoration: const InputDecoration(labelText: 'Course *'),
            items: _courses.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text('${c.courseCode} — ${c.courseName}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() => _courseId = v),
          ),
          const SizedBox(height: 12),

          // Lecturer
          DropdownButtonFormField<int>(
            value: _lecturerId,
            decoration: const InputDecoration(labelText: 'Lecturer *'),
            items: _lecturers.map((l) => DropdownMenuItem(
              value: l.id,
              child: Text(l.fullName, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() => _lecturerId = v),
          ),
          const SizedBox(height: 12),

          // Date picker
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Requested Date *'),
              child: Text(
                _requestedDate != null
                    ? _requestedDate!.toIso8601String().split('T').first
                    : 'Tap to pick a date',
                style: AppTypography.bodyMedium.copyWith(
                  color: _requestedDate == null ? AppColors.textSecondary : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Day
          DropdownButtonFormField<String>(
            value: _day,
            decoration: const InputDecoration(labelText: 'Day of Week'),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => _day = v!),
          ),
          const SizedBox(height: 12),

          // Start + End time
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _startTime,
                decoration: const InputDecoration(labelText: 'Start Time'),
                items: _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
                onChanged: (v) => setState(() => _startTime = v!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _endTime,
                decoration: const InputDecoration(labelText: 'End Time'),
                items: _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
                onChanged: (v) => setState(() => _endTime = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Reason
          TextFormField(
            controller: _reasonController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason *',
              hintText: 'Why is this emergency session needed?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withAlpha(60)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The system will check for scheduling conflicts. You can submit even if conflicts exist — a coordinator must approve.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          color: AppColors.textOnPrimary, strokeWidth: 2))
                  : const Text('Submit Request',
                      style: TextStyle(color: AppColors.textOnPrimary)),
            ),
          ),
        ],
      ]),
    );
  }
}
