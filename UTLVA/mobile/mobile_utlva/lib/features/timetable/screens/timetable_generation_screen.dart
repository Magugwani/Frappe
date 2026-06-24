import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/generation_result.dart';
import '../services/timetable_service.dart';

class TimetableGenerationScreen extends StatefulWidget {
  const TimetableGenerationScreen({super.key});
  @override
  State<TimetableGenerationScreen> createState() => _TimetableGenerationScreenState();
}

class _TimetableGenerationScreenState extends State<TimetableGenerationScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  List<Programme> _programmes = [];

  AcademicYear? _selectedYear;
  Semester? _selectedSemester;
  Programme? _selectedProgramme;

  bool _dryRun = true;
  bool _loading = false;
  bool _refLoaded = false;
  GenerationResult? _result;

  @override
  void initState() {
    super.initState();
    _loadRef();
  }

  Future<void> _loadRef() async {
    try {
      final r = await Future.wait([
        _acService.getYears(),
        _acService.getSemesters(),
        _acService.getProgrammes(),
      ]);
      _years = r[0] as List<AcademicYear>;
      _semesters = r[1] as List<Semester>;
      _programmes = r[2] as List<Programme>;

      if (mounted) {
        setState(() {
          _selectedYear = _years.firstWhere((y) => y.isActive,
              orElse: () => _years.isNotEmpty ? _years.first : _years.first);
          if (_semesters.isNotEmpty) {
            _selectedSemester = _semesters.firstWhere(
                (s) => _selectedYear != null && s.academicYearId == _selectedYear!.id,
                orElse: () => _semesters.first);
          }
          if (_programmes.isNotEmpty) _selectedProgramme = _programmes.first;
          _refLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _run() async {
    if (_selectedYear == null || _selectedSemester == null || _selectedProgramme == null) {
      _showSnack('Select academic year, semester, and programme.', isError: true);
      return;
    }
    setState(() { _loading = true; _result = null; });
    try {
      final result = await _ttService.generateTimetable(
        academicYearId: _selectedYear!.id,
        semesterId: _selectedSemester!.id,
        programmeId: _selectedProgramme!.id,
        dryRun: _dryRun,
      );
      if (mounted) setState(() { _result = result; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Generation failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Generate Timetable'),
      body: _loading ? _buildLoading() : _buildBody(),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: AppColors.primary),
      const SizedBox(height: 20),
      Text(
        _dryRun ? 'Computing schedule preview…' : 'Generating timetable…',
        style: AppTypography.titleMedium,
      ),
      const SizedBox(height: 6),
      const Text(
        'Checking all periods, venues, and constraints.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    ]),
  );

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildConfigCard(),
      const SizedBox(height: 16),
      if (_result == null) _buildAlgorithmInfo(),
      if (_result != null) ...[
        _buildResultSummary(),
        if (_result!.failedSessions > 0) ...[const SizedBox(height: 16), _buildFailedList()],
        const SizedBox(height: 16),
        _buildGeneratedList(),
        if (_result!.dryRun && _result!.generatedSessions > 0) ...[
          const SizedBox(height: 16),
          _buildCommitPrompt(),
        ],
      ],
    ]),
  );

  // ── Config card ───────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Generation Configuration', style: AppTypography.titleLarge),
        const SizedBox(height: 16),

        // Academic Year
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

        // Semester
        DropdownButtonFormField<Semester>(
          value: _selectedSemester,
          decoration: InputDecoration(
            labelText: 'Semester',
            isDense: true,
            helperText: _selectedSemester != null
                ? '${_selectedSemester!.teachingPeriodCount} active teaching periods'
                : null,
          ),
          items: _semesters
              .where((s) => _selectedYear == null || s.academicYearId == _selectedYear!.id)
              .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
              .toList(),
          onChanged: (s) => setState(() { _selectedSemester = s; _result = null; }),
        ),
        const SizedBox(height: 12),

        // Programme — single dropdown as specified
        DropdownButtonFormField<Programme>(
          value: _selectedProgramme,
          decoration: const InputDecoration(
            labelText: 'Programme',
            isDense: true,
            helperText: 'Generator will schedule courses for this programme only.',
          ),
          items: _programmes.map((p) => DropdownMenuItem(
            value: p,
            child: Text('${p.code} — ${p.name}', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (p) => setState(() { _selectedProgramme = p; _result = null; }),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),

        // Dry run toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Preview Mode', style: AppTypography.titleMedium),
          subtitle: Text(
            _dryRun
                ? 'Computes the schedule without writing to the database. Review results first.'
                : 'Will write DRAFT entries directly to the database.',
            style: AppTypography.bodySmall,
          ),
          value: _dryRun,
          activeColor: AppColors.accent,
          onChanged: (v) => setState(() { _dryRun = v; _result = null; }),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _refLoaded ? _run : null,
            icon: Icon(_dryRun ? Icons.preview_outlined : Icons.auto_fix_high),
            label: Text(_dryRun ? 'Preview Schedule' : 'Generate Timetable'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dryRun ? AppColors.accent : AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              minimumSize: const Size(0, 52),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Algorithm info ────────────────────────────────────────────────────────

  Widget _buildAlgorithmInfo() {
    const steps = [
      ('Load', 'All courses, groups, lecturers, venues, and teaching periods for the selected semester'),
      ('Queue', 'One scheduling task per course × student group × session\n(4h course = 2 sessions per group)'),
      ('Check', 'Lecturer, group, and venue checked with full time-overlap logic\n(A_start < B_end AND A_end > B_start)'),
      ('Venue', 'Smallest venue that fits: capacity ≥ student count + type + resources'),
      ('Create', 'DRAFT TimetableEntry — visible in Timetable Management after generation'),
    ];
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info_outline, color: AppColors.accent, size: 18),
          const SizedBox(width: 6),
          Text('How the generator works', style: AppTypography.titleMedium),
        ]),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: AppColors.primary.withAlpha(20), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('${e.key + 1}', style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value.$1, style: AppTypography.labelLarge.copyWith(color: AppColors.primary)),
              Text(e.value.$2, style: AppTypography.bodySmall),
            ])),
          ]),
        )),
      ]),
    );
  }

  // ── Result summary ────────────────────────────────────────────────────────

  Widget _buildResultSummary() {
    final r = _result!;
    return ReusableCard(
      backgroundColor: r.generatedSessions > 0
          ? AppColors.statusFree.withAlpha(12)
          : AppColors.statusExpired.withAlpha(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            r.generatedSessions > 0 ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: r.generatedSessions > 0 ? AppColors.statusFree : AppColors.statusInUse,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(r.dryRun ? 'Preview Result' : 'Generation Complete', style: AppTypography.titleLarge),
        ]),
        const SizedBox(height: 4),
        Text('${r.academicYear} — ${r.semester} | ${r.programme}', style: AppTypography.bodySmall),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _statCard('Generated', '${r.generatedSessions}', AppColors.statusFree, 'sessions')),
          const SizedBox(width: 12),
          Expanded(child: _statCard('Failed', '${r.failedSessions}', r.failedSessions > 0 ? AppColors.statusExpired : AppColors.textSecondary, 'sessions')),
        ]),
        if (r.dryRun) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.accent.withAlpha(20), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.preview, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text('Preview only — no entries were written to the database.', style: AppTypography.bodySmall.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _statCard(String label, String value, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: AppTypography.headlineLarge.copyWith(color: color)),
        Text(label, style: AppTypography.labelMedium),
        Text(subtitle, style: AppTypography.caption),
      ]),
    );
  }

  // ── Failed list ───────────────────────────────────────────────────────────

  Widget _buildFailedList() {
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.error_outline, color: AppColors.statusExpired, size: 18),
          const SizedBox(width: 6),
          Text('Failed Sessions (${_result!.failedSessions})',
              style: AppTypography.titleMedium.copyWith(color: AppColors.statusExpired)),
        ]),
        const SizedBox(height: 10),
        ..._result!.failed.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.statusExpired.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.statusExpired.withAlpha(40)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(f.courseCode, style: AppTypography.labelLarge.copyWith(color: AppColors.statusExpired)),
                const SizedBox(width: 6),
                Text('Session ${f.session}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ]),
              if (f.group.isNotEmpty && f.group != '—')
                Text(f.group, style: AppTypography.bodySmall),
              const SizedBox(height: 4),
              Text(f.reason, style: AppTypography.bodySmall.copyWith(color: AppColors.statusExpired)),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── Generated list ────────────────────────────────────────────────────────

  Widget _buildGeneratedList() {
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_outline, color: AppColors.statusFree, size: 18),
          const SizedBox(width: 6),
          Text('Generated Sessions (${_result!.generatedSessions})',
              style: AppTypography.titleMedium.copyWith(color: AppColors.statusFree)),
        ]),
        const SizedBox(height: 10),
        ..._result!.generated.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.statusFree.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.statusFree.withAlpha(40)),
            ),
            child: Row(children: [
              Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(5)),
                  child: Text(e.courseCode, style: AppTypography.caption.copyWith(color: AppColors.textOnPrimary, fontWeight: FontWeight.w800, fontSize: 10)),
                ),
                const SizedBox(height: 2),
                Text(e.session, style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontSize: 9)),
              ]),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.courseName, style: AppTypography.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${e.group} · ${e.lecturer}', style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${e.day.substring(0, 3)} ${e.time}',
                    style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                Text(e.venue, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── Commit prompt ─────────────────────────────────────────────────────────

  Widget _buildCommitPrompt() {
    return ReusableCard(
      backgroundColor: AppColors.primary.withAlpha(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ready to Commit?', style: AppTypography.titleMedium),
        const SizedBox(height: 6),
        Text(
          'The preview looks good. Disable Preview Mode and tap Generate Timetable '
          'to write ${_result!.generatedSessions} DRAFT entries to the database.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() { _dryRun = false; _result = null; }),
              child: const Text('Switch to Commit Mode'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/timetable/coordinator'),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: const Text('View Timetable'),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.statusFree,
    ));
  }
}
