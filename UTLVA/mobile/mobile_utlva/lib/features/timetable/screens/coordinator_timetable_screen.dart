import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/timetable_grid_view.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../../../features/venues/models/venue_models.dart';
import '../../../features/venues/services/venues_service.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';

class CoordinatorTimetableScreen extends StatefulWidget {
  const CoordinatorTimetableScreen({super.key});
  @override
  State<CoordinatorTimetableScreen> createState() => _CoordinatorTimetableScreenState();
}

class _CoordinatorTimetableScreenState extends State<CoordinatorTimetableScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();
  final _vService = VenuesService();

  // Reference data
  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  List<Programme> _programmes = [];
  List<StudentGroup> _groups = [];
  List<Course> _courses = [];
  List<Lecturer> _lecturers = [];
  List<Venue> _venues = [];

  // Filter selections
  AcademicYear? _selectedYear;
  Semester? _selectedSemester;
  Programme? _selectedProgramme;

  // Timetable entries
  List<TimetableEntry> _entries = [];
  bool _loading = true;
  bool _refDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  Future<void> _loadRefData() async {
    try {
      final results = await Future.wait([
        _acService.getYears(),
        _acService.getSemesters(),
        _acService.getProgrammes(),
        _acService.getLecturers(),
        _vService.getVenues(),
      ]);
      setState(() {
        _years = results[0] as List<AcademicYear>;
        _semesters = results[1] as List<Semester>;
        _programmes = results[2] as List<Programme>;
        _lecturers = results[3] as List<Lecturer>;
        _venues = results[4] as List<Venue>;
        if (_years.isNotEmpty) _selectedYear = _years.first;
        if (_semesters.isNotEmpty) _selectedSemester = _semesters.first;
        if (_programmes.isNotEmpty) _selectedProgramme = _programmes.first;
        _refDataLoaded = true;
      });
      await _loadEntries();
      await _loadGroups();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadGroups() async {
    if (_selectedProgramme == null) return;
    final groups = await _acService.getGroups(programmeId: _selectedProgramme!.id);
    final courses = await _acService.getCourses(programmeId: _selectedProgramme!.id);
    setState(() { _groups = groups; _courses = courses; });
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      _entries = await _ttService.getEntries(
        academicYearId: _selectedYear?.id,
        semesterId: _selectedSemester?.id,
        programmeId: _selectedProgramme?.id,
      );
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Timetable Management',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: AppColors.textOnPrimary),
            tooltip: 'Auto-Generate Timetable',
            onPressed: () => context.push('/timetable/generate'),
          ),
        ],
      ),
      floatingActionButton: _refDataLoaded
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: AppColors.textOnPrimary),
              label: const Text('Add Entry', style: TextStyle(color: AppColors.textOnPrimary)),
              onPressed: () => _showEntryForm(context),
            )
          : null,
      body: Column(
        children: [
          _buildFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _entries.isEmpty
                    ? _buildEmpty()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryBar(),
                            const SizedBox(height: 12),
                            TimetableGridView(
                              entries: _entries,
                              onEntryTap: (e) => _showEntryForm(context, entry: e),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterDropdown<AcademicYear>(
              label: 'Year',
              value: _selectedYear,
              items: _years,
              displayText: (y) => y.name,
              onChanged: (y) { setState(() => _selectedYear = y); _loadEntries(); },
            ),
            const SizedBox(width: 10),
            _FilterDropdown<Semester>(
              label: 'Semester',
              value: _selectedSemester,
              items: _semesters,
              displayText: (s) => s.name,
              onChanged: (s) { setState(() => _selectedSemester = s); _loadEntries(); },
            ),
            const SizedBox(width: 10),
            _FilterDropdown<Programme>(
              label: 'Programme',
              value: _selectedProgramme,
              items: _programmes,
              displayText: (p) => p.code,
              onChanged: (p) { setState(() => _selectedProgramme = p); _loadGroups(); _loadEntries(); },
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reload'),
              onPressed: _loadEntries,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final published = _entries.where((e) => e.status == 'PUBLISHED').length;
    final draft = _entries.where((e) => e.status == 'DRAFT').length;
    return Row(children: [
      _SummaryChip(label: 'Total', count: _entries.length, color: AppColors.primary),
      const SizedBox(width: 8),
      _SummaryChip(label: 'Published', count: published, color: AppColors.statusFree),
      const SizedBox(width: 8),
      _SummaryChip(label: 'Draft', count: draft, color: AppColors.statusInUse),
    ]);
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.calendar_month_outlined, size: 56, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text('No timetable entries', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Text('Use the + button to add the first entry.', style: AppTypography.bodySmall),
    ]),
  );

  // ── Entry form ──────────────────────────────────────────────────────────────
  void _showEntryForm(BuildContext context, {TimetableEntry? entry}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EntryForm(
        entry: entry,
        years: _years, semesters: _semesters, programmes: _programmes,
        groups: _groups, courses: _courses, lecturers: _lecturers, venues: _venues,
        onSaved: (e) async {
          Navigator.pop(ctx);
          try {
            entry == null ? await _ttService.createEntry(e) : await _ttService.updateEntry(e);
            _loadEntries();
          } catch (err) {
            if (mounted) _showError(err);
          }
        },
        onDelete: entry == null ? null : (e) async {
          Navigator.pop(ctx);
          try { await _ttService.deleteEntry(e.id); _loadEntries(); } catch (err) { if (mounted) _showError(err); }
        },
      ),
    );
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
  }
}

// ── Entry form widget ─────────────────────────────────────────────────────────
class _EntryForm extends StatefulWidget {
  final TimetableEntry? entry;
  final List<AcademicYear> years;
  final List<Semester> semesters;
  final List<Programme> programmes;
  final List<StudentGroup> groups;
  final List<Course> courses;
  final List<Lecturer> lecturers;
  final List<Venue> venues;
  final Future<void> Function(TimetableEntry) onSaved;
  final Future<void> Function(TimetableEntry)? onDelete;

  const _EntryForm({
    this.entry,
    required this.years, required this.semesters, required this.programmes,
    required this.groups, required this.courses, required this.lecturers,
    required this.venues, required this.onSaved, this.onDelete,
  });

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late int? _yearId, _semId, _progId, _groupId, _courseId, _lecturerId, _venueId;
  late String _day, _startTime, _endTime, _status;
  bool _saving = false;

  static const _days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
  static const _times = [
    '07:00:00', '08:00:00', '09:00:00', '10:00:00', '11:00:00', '12:00:00',
    '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00', '18:00:00',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _yearId = e?.academicYearId ?? (widget.years.isNotEmpty ? widget.years.first.id : null);
    _semId = e?.semesterId ?? (widget.semesters.isNotEmpty ? widget.semesters.first.id : null);
    _progId = e?.programmeId ?? (widget.programmes.isNotEmpty ? widget.programmes.first.id : null);
    _groupId = e?.studentGroupId;
    _courseId = e?.courseId ?? (widget.courses.isNotEmpty ? widget.courses.first.id : null);
    _lecturerId = e?.lecturerId ?? (widget.lecturers.isNotEmpty ? widget.lecturers.first.id : null);
    _venueId = e?.venueId;
    _day = e?.dayOfWeek ?? 'MONDAY';
    _startTime = e?.startTime ?? '08:00:00';
    _endTime = e?.endTime ?? '10:00:00';
    _status = e?.status ?? 'DRAFT';
  }

  String _timeLabel(String t) {
    final parts = t.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _yearId == null || _courseId == null || _lecturerId == null) return;
    setState(() => _saving = true);
    final entry = TimetableEntry(
      id: widget.entry?.id ?? 0,
      academicYearId: _yearId!, academicYearName: '',
      semesterId: _semId!, semesterName: '',
      programmeId: _progId!, programmeName: '', programmeCode: '',
      studentGroupId: _groupId, studentGroupName: null,
      courseId: _courseId!, courseCode: '', courseName: '',
      lecturerId: _lecturerId!, lecturerName: '',
      venueId: _venueId, venueCode: null, venueName: null,
      dayOfWeek: _day, startTime: _startTime, endTime: _endTime, status: _status,
    );
    await widget.onSaved(entry);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isEdit ? 'Edit Timetable Entry' : 'New Timetable Entry', style: AppTypography.headlineMedium),
            if (isEdit && widget.onDelete != null)
              IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.error), onPressed: () => widget.onDelete!(widget.entry!)),
          ]),
          const SizedBox(height: 20),

          // Academic Year + Semester
          Row(children: [
            Expanded(child: _dd<int?>('Year', _yearId, widget.years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.name))).toList(), (v) => setState(() => _yearId = v))),
            const SizedBox(width: 10),
            Expanded(child: _dd<int?>('Semester', _semId, widget.semesters.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(), (v) => setState(() => _semId = v))),
          ]),
          const SizedBox(height: 12),

          // Programme + Group
          Row(children: [
            Expanded(child: _dd<int?>('Programme', _progId, widget.programmes.map((p) => DropdownMenuItem(value: p.id, child: Text(p.code))).toList(), (v) => setState(() => _progId = v))),
            const SizedBox(width: 10),
            Expanded(child: _dd<int?>('Group', _groupId,
              [const DropdownMenuItem(value: null, child: Text('All groups')), ...widget.groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.groupName)))],
              (v) => setState(() => _groupId = v))),
          ]),
          const SizedBox(height: 12),

          // Course
          _dd<int?>('Course', _courseId, widget.courses.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.courseCode} — ${c.courseName}', overflow: TextOverflow.ellipsis))).toList(), (v) => setState(() => _courseId = v)),
          const SizedBox(height: 12),

          // Lecturer + Venue
          Row(children: [
            Expanded(child: _dd<int?>('Lecturer', _lecturerId, widget.lecturers.map((l) => DropdownMenuItem(value: l.id, child: Text(l.fullName, overflow: TextOverflow.ellipsis))).toList(), (v) => setState(() => _lecturerId = v))),
            const SizedBox(width: 10),
            Expanded(child: _dd<int?>('Venue', _venueId,
              [const DropdownMenuItem(value: null, child: Text('No venue')), ...widget.venues.map((v) => DropdownMenuItem(value: v.id, child: Text(v.code)))],
              (v) => setState(() => _venueId = v))),
          ]),
          const SizedBox(height: 12),

          // Day
          _dd<String>('Day', _day, _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(), (v) => setState(() => _day = v!)),
          const SizedBox(height: 12),

          // Start + End time
          Row(children: [
            Expanded(child: _dd<String>('Start', _startTime, _times.map((t) => DropdownMenuItem(value: t, child: Text(_timeLabel(t)))).toList(), (v) => setState(() => _startTime = v!))),
            const SizedBox(width: 10),
            Expanded(child: _dd<String>('End', _endTime, _times.map((t) => DropdownMenuItem(value: t, child: Text(_timeLabel(t)))).toList(), (v) => setState(() => _endTime = v!))),
          ]),
          const SizedBox(height: 12),

          // Status
          _dd<String>('Status', _status,
            ['DRAFT', 'PUBLISHED'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            (v) => setState(() => _status = v!)),
          const SizedBox(height: 24),

          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                : Text(isEdit ? 'Save Changes' : 'Create Entry'),
          )),
        ]),
      ),
    );
  }

  Widget _dd<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) displayText;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({required this.label, this.value, required this.items, required this.displayText, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: DropdownButtonFormField<T>(
        value: value,
        isDense: true,
        decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(displayText(i), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label; final int count; final Color color;
  const _SummaryChip({required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(16)),
      child: Text('$label: $count', style: AppTypography.labelMedium.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
