import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_conflict.dart';
import '../services/timetable_service.dart';

class TimetableValidationScreen extends StatefulWidget {
  const TimetableValidationScreen({super.key});
  @override
  State<TimetableValidationScreen> createState() => _TimetableValidationScreenState();
}

class _TimetableValidationScreenState extends State<TimetableValidationScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  AcademicYear? _selectedYear;
  Semester? _selectedSemester;

  bool _loading = false;
  bool _refLoaded = false;
  ValidationResult? _result;

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
          _selectedYear = _years.firstWhere((y) => y.isActive,
              orElse: () => _years.isNotEmpty ? _years.first : _years.first);
          if (_semesters.isNotEmpty) {
            _selectedSemester = _semesters.firstWhere(
              (s) => _selectedYear != null && s.academicYearId == _selectedYear!.id,
              orElse: () => _semesters.first,
            );
          }
          _refLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _validate() async {
    if (_selectedYear == null || _selectedSemester == null) return;
    setState(() { _loading = true; _result = null; });
    try {
      final result = await _ttService.validateTimetable(
        academicYearId: _selectedYear!.id,
        semesterId: _selectedSemester!.id,
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Validation failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Timetable Validation'),
      body: _loading ? _buildLoading() : _buildBody(),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: AppColors.primary),
      const SizedBox(height: 16),
      Text('Running conflict detection…', style: AppTypography.titleMedium),
      const SizedBox(height: 4),
      Text('Checking all entries for venue, lecturer, and group conflicts.',
          style: AppTypography.bodySmall, textAlign: TextAlign.center),
    ]),
  );

  Widget _buildBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildConfigCard(),
      const SizedBox(height: 16),
      if (_result != null) ...[
        _buildStatusBanner(),
        const SizedBox(height: 16),
        _buildConflictSummary(),
        if (_result!.conflicts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildConflictList(),
        ],
      ] else
        _buildInfoCard(),
    ]),
  );

  // ── Config card ───────────────────────────────────────────────────────────

  Widget _buildConfigCard() => ReusableCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Validation Configuration', style: AppTypography.titleLarge),
      const SizedBox(height: 16),
      DropdownButtonFormField<AcademicYear>(
        value: _selectedYear,
        decoration: const InputDecoration(labelText: 'Academic Year', isDense: true),
        items: _years.map((y) => DropdownMenuItem(
          value: y,
          child: Row(children: [
            Text(y.name),
            if (y.isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.statusFree.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: Text('ACTIVE', style: AppTypography.caption.copyWith(color: AppColors.statusFree, fontWeight: FontWeight.w700, fontSize: 9)),
              ),
            ],
          ]),
        )).toList(),
        onChanged: (y) => setState(() {
          _selectedYear = y;
          _selectedSemester = _semesters.firstWhere(
            (s) => y != null && s.academicYearId == y.id,
            orElse: () => _semesters.isNotEmpty ? _semesters.first : _semesters.first,
          );
          _result = null;
        }),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<Semester>(
        value: _selectedSemester,
        decoration: const InputDecoration(labelText: 'Semester', isDense: true),
        items: _semesters
            .where((s) => _selectedYear == null || s.academicYearId == _selectedYear!.id)
            .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
            .toList(),
        onChanged: (s) => setState(() { _selectedSemester = s; _result = null; }),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _refLoaded ? _validate : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Validate Timetable'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      ),
    ]),
  );

  // ── Status banner ─────────────────────────────────────────────────────────

  Widget _buildStatusBanner() {
    final passed = _result!.isPassed;
    final color = passed ? AppColors.statusFree : AppColors.statusExpired;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80), width: 1.5),
      ),
      child: Row(children: [
        Icon(
          passed ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          color: color, size: 36,
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            passed ? '✓ No Conflicts Found' : '⚠ Conflicts Detected',
            style: AppTypography.titleLarge.copyWith(color: color),
          ),
          Text(
            passed
                ? '${_result!.validatedEntries} entries promoted to VALIDATED.'
                : '${_result!.totalConflicts} conflict(s) must be resolved before validating.',
            style: AppTypography.bodySmall.copyWith(color: color),
          ),
        ])),
      ]),
    );
  }

  // ── Conflict summary chips ─────────────────────────────────────────────────

  Widget _buildConflictSummary() => ReusableCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Validation Report', style: AppTypography.titleMedium),
      const SizedBox(height: 4),
      Text('${_result!.academicYear} — ${_result!.semester}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _statChip('Entries Checked', '${_result!.totalEntriesChecked}', AppColors.primary)),
        const SizedBox(width: 8),
        Expanded(child: _statChip('Total Conflicts', '${_result!.totalConflicts}',
            _result!.totalConflicts > 0 ? AppColors.statusExpired : AppColors.statusFree)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _statChip('Venue', '${_result!.venueConflicts}',
            _result!.venueConflicts > 0 ? AppColors.statusExpired : AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: _statChip('Lecturer', '${_result!.lecturerConflicts}',
            _result!.lecturerConflicts > 0 ? AppColors.statusExpired : AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: _statChip('Group', '${_result!.studentGroupConflicts}',
            _result!.studentGroupConflicts > 0 ? AppColors.statusExpired : AppColors.textSecondary)),
      ]),
    ]),
  );

  Widget _statChip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(color: color.withAlpha(15), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(value, style: AppTypography.headlineMedium.copyWith(color: color)),
      Text(label, style: AppTypography.caption, textAlign: TextAlign.center),
    ]),
  );

  // ── Conflict list ─────────────────────────────────────────────────────────

  Widget _buildConflictList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Conflict Details', style: AppTypography.titleLarge),
      const SizedBox(height: 10),
      ..._result!.conflicts.map(_buildConflictCard),
    ],
  );

  Widget _buildConflictCard(TimetableConflict c) {
    final (icon, color) = switch (c.conflictType) {
      'VENUE_CONFLICT' => (Icons.location_city_outlined, AppColors.statusInUse),
      'LECTURER_CONFLICT' => (Icons.person_outlined, AppColors.statusExpired),
      _ => (Icons.group_outlined, AppColors.statusBooked),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReusableCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(c.typeDisplay, style: AppTypography.titleMedium.copyWith(color: color)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(c.message, style: AppTypography.bodySmall),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _entryRow('Entry A', c.entryA),
          const SizedBox(height: 4),
          _entryRow('Entry B', c.entryB),
        ]),
      ),
    );
  }

  Widget _entryRow(String label, ConflictEntry e) => Row(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primary.withAlpha(20), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
    ),
    const SizedBox(width: 8),
    Text('${e.course}  •  ${e.day}  ${e.time}', style: AppTypography.bodySmall),
  ]);

  // ── Info card (before first run) ──────────────────────────────────────────

  Widget _buildInfoCard() => ReusableCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.info_outline, color: AppColors.accent, size: 18),
        const SizedBox(width: 6),
        Text('What validation checks', style: AppTypography.titleMedium),
      ]),
      const SizedBox(height: 12),
      _infoRow(Icons.location_city_outlined, AppColors.statusInUse,
          'Venue Conflicts', 'One venue cannot have two sessions at the same time.'),
      const SizedBox(height: 8),
      _infoRow(Icons.person_outlined, AppColors.statusExpired,
          'Lecturer Conflicts', 'One lecturer cannot teach two groups simultaneously.'),
      const SizedBox(height: 8),
      _infoRow(Icons.group_outlined, AppColors.statusBooked,
          'Student Group Conflicts', 'One student group cannot attend two sessions at the same time.'),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.statusFree.withAlpha(15), borderRadius: BorderRadius.circular(8)),
        child: Text(
          'If validation PASSES, all DRAFT entries are automatically promoted to VALIDATED.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.statusFree, fontWeight: FontWeight.w600),
        ),
      ),
    ]),
  );

  Widget _infoRow(IconData icon, Color color, String title, String desc) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTypography.labelLarge.copyWith(color: color)),
        Text(desc, style: AppTypography.bodySmall),
      ])),
    ],
  );
}
