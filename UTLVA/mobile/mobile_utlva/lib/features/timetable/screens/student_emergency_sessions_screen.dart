import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/emergency_session.dart';
import '../services/timetable_service.dart';

/// FR-42 / FR-43 — Students view approved emergency sessions that affect their
/// student group, including updated time and venue locations.
class StudentEmergencySessionsScreen extends StatefulWidget {
  const StudentEmergencySessionsScreen({super.key});

  @override
  State<StudentEmergencySessionsScreen> createState() =>
      _StudentEmergencySessionsScreenState();
}

class _StudentEmergencySessionsScreenState
    extends State<StudentEmergencySessionsScreen> {
  final _ttService = TimetableService();

  List<EmergencySession> _sessions = [];
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
      final sessions = await _ttService.getStudentEmergencySessions();
      if (mounted) setState(() => _sessions = sessions);
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
        title: 'Emergency Sessions',
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
    if (_sessions.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _SessionCard(
          session: _sessions[i],
          onNavigate: _sessions[i].venueCode != null
              ? () => context.push('/venues/map')
              : null,
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_available, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('No emergency sessions',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('Approved extra sessions for your group will appear here.',
              style: AppTypography.bodySmall, textAlign: TextAlign.center),
        ]),
      );

  Widget _buildError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Could not load sessions', style: AppTypography.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      );
}

// ── Session card ───────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final EmergencySession session;
  final VoidCallback? onNavigate;

  const _SessionCard({required this.session, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.title.isNotEmpty ? session.title : session.courseCode,
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.textOnPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(status: session.status, label: session.statusDisplay),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Course full name
                Text(session.courseName,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),

                // Date & time row
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  text:
                      '${session.requestedDate}  ·  ${session.dayDisplay}  '
                      '${_fmt(session.startTime)} – ${_fmt(session.endTime)}',
                ),
                const SizedBox(height: 6),

                // Lecturer
                _InfoRow(
                  icon: Icons.person_outline,
                  text: 'Lecturer: ${session.lecturerName}',
                ),
                const SizedBox(height: 6),

                // Venue (FR-43 — show updated venue location)
                if (session.venueCode != null) ...[
                  _InfoRow(
                    icon: Icons.place_outlined,
                    text: '${session.venueCode}'
                        '${session.venueName != null ? " — ${session.venueName}" : ""}',
                  ),
                  const SizedBox(height: 6),
                ],

                // Reason
                _InfoRow(
                  icon: Icons.info_outline,
                  text: session.reason,
                  maxLines: 3,
                ),

                if (session.comments.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _InfoRow(
                    icon: Icons.notes_outlined,
                    text: session.comments,
                    maxLines: 2,
                  ),
                ],

                // Resources required
                if (session.requiredResources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: session.requiredResources
                        .map((r) => Chip(
                              label: Text(r.toString(),
                                  style: AppTypography.caption),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ))
                        .toList(),
                  ),
                ],

                // Navigate button (FR-39, FR-43)
                if (onNavigate != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onNavigate,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('View Venue on Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(String t) {
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final int maxLines;

  const _InfoRow({required this.icon, required this.text, this.maxLines = 2});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const _StatusBadge({required this.status, required this.label});

  Color get _color => switch (status) {
        'APPROVED' => AppColors.statusFree,
        'REJECTED' => AppColors.error,
        'CANCELLED' => AppColors.statusExpired,
        _ => AppColors.statusBooked,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _color.withAlpha(120)),
        ),
        child: Text(label,
            style: AppTypography.caption.copyWith(color: _color, fontWeight: FontWeight.w700)),
      );
}
