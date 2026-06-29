import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_lifecycle.dart';
import '../services/timetable_service.dart';

class TimetablePublishingScreen extends StatefulWidget {
  const TimetablePublishingScreen({super.key});
  @override
  State<TimetablePublishingScreen> createState() => _TimetablePublishingScreenState();
}

class _TimetablePublishingScreenState extends State<TimetablePublishingScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  AcademicYear? _selectedYear;
  Semester? _selectedSemester;

  TimetableStatusInfo? _statusInfo;
  bool _loading = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _loadRef();
  }

  Future<void> _loadRef() async {
    try {
      final r = await Future.wait([_acService.getYears(), _acService.getSemesters()]);
      _years = r[0] as List<AcademicYear>;
      _semesters = r[1] as List<Semester>;
      if (mounted) {
        setState(() {
          _selectedYear = _years.firstWhere((y) => y.isActive, orElse: () => _years.first);
          _selectedSemester = _semesters.firstWhere(
            (s) => _selectedYear != null && s.academicYearId == _selectedYear!.id,
            orElse: () => _semesters.first,
          );
        });
        await _loadStatus();
      }
    } catch (_) {}
  }

  Future<void> _loadStatus() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() => _loading = true);
    try {
      final info = await _ttService.getTimetableStatus(
        academicYearId: _selectedYear!.id,
        semesterId: _selectedSemester!.id,
      );
      if (mounted) setState(() => _statusInfo = info);
    } catch (_) {
      // ignore — status card simply won't show
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() => _acting = true);
    try {
      final result = await _ttService.publishTimetable(
        academicYearId: _selectedYear!.id,
        semesterId: _selectedSemester!.id,
      );
      if (!mounted) return;
      _showSnack(result.message, success: result.success);
      if (result.success) await _loadStatus();
    } catch (e) {
      if (mounted) _showSnack('Error: $e', success: false);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _validate() async {
    await context.push('/timetable/validate');
    // Refresh lifecycle status after the coordinator returns from validation
    if (mounted) await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Timetable Publishing', showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSemesterSelector(),
                const SizedBox(height: 16),
                if (_statusInfo != null) ...[
                  _buildLifecycleCard(),
                  const SizedBox(height: 16),
                  _buildActionButtons(),
                  const SizedBox(height: 16),
                  _buildEntryCountsCard(),
                  if (_statusInfo!.lastPublication != null) ...[
                    const SizedBox(height: 16),
                    _buildLastPublicationCard(),
                  ],
                ],
              ]),
            ),
    );
  }

  // ── Semester selector ─────────────────────────────────────────────────────

  Widget _buildSemesterSelector() => ReusableCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Select Semester', style: AppTypography.titleMedium),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<AcademicYear>(
          value: _selectedYear,
          decoration: const InputDecoration(labelText: 'Academic Year', isDense: true),
          items: _years.map((y) => DropdownMenuItem(
            value: y,
            child: Row(children: [
              Text(y.name),
              if (y.isActive) ...[const SizedBox(width: 6), Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.statusFree.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: Text('ACTIVE', style: AppTypography.caption.copyWith(color: AppColors.statusFree, fontWeight: FontWeight.w700, fontSize: 9)),
              )],
            ]),
          )).toList(),
          onChanged: (y) { setState(() { _selectedYear = y; _selectedSemester = null; _statusInfo = null; }); },
        )),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<Semester>(
          value: _selectedSemester,
          decoration: const InputDecoration(labelText: 'Semester', isDense: true),
          items: _semesters
              .where((s) => _selectedYear == null || s.academicYearId == _selectedYear!.id)
              .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
              .toList(),
          onChanged: (s) { setState(() { _selectedSemester = s; _statusInfo = null; }); _loadStatus(); },
        )),
      ]),
    ]),
  );

  // ── Lifecycle status card ─────────────────────────────────────────────────

  Widget _buildLifecycleCard() {
    final info = _statusInfo!;
    final (icon, color, description) = switch (info.dominantStatus) {
      'PUBLISHED' => (Icons.public, AppColors.statusFree, 'Timetable is live. Students and lecturers can view it.'),
      'VALIDATED' => (Icons.verified_outlined, AppColors.statusBooked, 'Timetable validated. Ready to publish if no conflicts exist.'),
      'DRAFT' => (Icons.edit_note_outlined, AppColors.statusInUse, 'Timetable is in draft. Validate before publishing.'),
      _ => (Icons.inbox_outlined, AppColors.textSecondary, 'No timetable entries yet.'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Current Status', style: AppTypography.bodySmall.copyWith(color: color)),
            Text(info.dominantStatus, style: AppTypography.headlineLarge.copyWith(color: color)),
          ]),
        ]),
        const SizedBox(height: 10),
        Text(description, style: AppTypography.bodySmall),
        if (info.openConflicts > 0) ...[
          const SizedBox(height: 8),
          _warningRow('${info.openConflicts} open conflict(s) must be resolved before publishing.'),
        ],
      ]),
    );
  }

  Widget _warningRow(String msg) => Row(children: [
    const Icon(Icons.warning_amber_outlined, color: AppColors.statusInUse, size: 16),
    const SizedBox(width: 6),
    Expanded(child: Text(msg, style: AppTypography.bodySmall.copyWith(color: AppColors.statusInUse))),
  ]);

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    final info = _statusInfo!;
    return Column(children: [
      // Validate button (available for DRAFT or when DRAFT entries exist)
      if (info.canValidate || info.draftCount > 0)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Validate Timetable'),
            onPressed: _acting ? null : _validate,
          ),
        ),
      if (info.canValidate || info.draftCount > 0) const SizedBox(height: 10),

      // Publish button (available only when VALIDATED + no conflicts)
      if (info.dominantStatus == 'VALIDATED' || info.validatedCount > 0)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _acting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                : const Icon(Icons.publish_outlined),
            label: Text(info.canPublish ? 'Publish Timetable' : 'Cannot Publish (${info.openConflicts} conflicts)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: info.canPublish ? AppColors.statusFree : AppColors.textSecondary,
              foregroundColor: AppColors.textOnPrimary,
              minimumSize: const Size(0, 52),
            ),
            onPressed: (_acting || !info.canPublish) ? null : _publish,
          ),
        ),

      // View conflicts button
      if (info.openConflicts > 0) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.statusExpired),
            label: Text('Resolve ${info.openConflicts} Conflict(s)', style: const TextStyle(color: AppColors.statusExpired)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.statusExpired)),
            onPressed: () => context.push('/timetable/conflicts'),
          ),
        ),
      ],

      // Published — view timetable button
      if (info.dominantStatus == 'PUBLISHED') ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('View Official Timetable'),
            onPressed: () => context.push('/timetable/coordinator'),
          ),
        ),
      ],
    ]);
  }

  // ── Entry counts card ─────────────────────────────────────────────────────

  Widget _buildEntryCountsCard() {
    final info = _statusInfo!;
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Entry Breakdown', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _countChip('Total', info.totalEntries, AppColors.primary)),
          const SizedBox(width: 8),
          Expanded(child: _countChip('Draft', info.draftCount, AppColors.statusInUse)),
          const SizedBox(width: 8),
          Expanded(child: _countChip('Validated', info.validatedCount, AppColors.statusBooked)),
          const SizedBox(width: 8),
          Expanded(child: _countChip('Published', info.publishedCount, AppColors.statusFree)),
        ]),
        if (info.openConflicts > 0 || info.resolvedConflicts > 0) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _countChip('Open Conflicts', info.openConflicts, AppColors.statusExpired)),
            const SizedBox(width: 8),
            Expanded(child: _countChip('Resolved', info.resolvedConflicts, AppColors.statusFree)),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
            const Expanded(child: SizedBox.shrink()),
          ]),
        ],
      ]),
    );
  }

  Widget _countChip(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(color: color.withAlpha(15), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text('$count', style: AppTypography.headlineMedium.copyWith(color: color)),
      Text(label, style: AppTypography.caption, textAlign: TextAlign.center),
    ]),
  );

  // ── Last publication ──────────────────────────────────────────────────────

  Widget _buildLastPublicationCard() {
    final pub = _statusInfo!.lastPublication!;
    return ReusableCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        const Icon(Icons.history, color: AppColors.accent, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Last Published', style: AppTypography.labelLarge.copyWith(color: AppColors.accent)),
          Text('By ${pub.publishedBy ?? 'Unknown'} · ${pub.entries} entries', style: AppTypography.bodySmall),
          if (pub.publishedAt != null) Text(pub.publishedAt!.substring(0, 10), style: AppTypography.caption),
        ])),
      ]),
    );
  }

  void _showSnack(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.statusFree : AppColors.error,
    ));
  }
}
