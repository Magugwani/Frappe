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
import '../models/venue_recommendation.dart';
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

  int _loadSeq = 0;

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
        _acService.getCourses(),
      ]);
      setState(() {
        _years = results[0] as List<AcademicYear>;
        _semesters = results[1] as List<Semester>;
        _programmes = results[2] as List<Programme>;
        _lecturers = results[3] as List<Lecturer>;
        _venues = results[4] as List<Venue>;
        _courses = results[5] as List<Course>;
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
    setState(() => _groups = groups);
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    try {
      final entries = await _ttService.getEntries(
        academicYearId: _selectedYear?.id,
        semesterId: _selectedSemester?.id,
        programmeId: _selectedProgramme?.id,
      );
      if (mounted && seq == _loadSeq) {
        setState(() => _entries = entries);
      }
    } catch (_) {
      if (mounted && seq == _loadSeq) {
        setState(() => _entries = []);
      }
    } finally {
      if (mounted && seq == _loadSeq) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Timetable Management',
        showBackButton: true,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined, color: AppColors.textOnPrimary),
            tooltip: 'Validate Timetable',
            onPressed: () => context.push('/timetable/validate'),
          ),
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
                ? const Center(child: CircularProgressIndicator(color: AppColors.statusBooked))
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
      child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterDropdown<AcademicYear>(
              label: 'Year',
              value: _selectedYear,
              items: _years,
              displayText: (y) => y.name,
              onChanged: (y) {
                setState(() => _selectedYear = y);
                _loadEntries();
              },
            ),
            _FilterDropdown<Semester>(
              label: 'Semester',
              value: _selectedSemester,
              items: _semesters,
              displayText: (s) => s.name,
              onChanged: (s) {
                setState(() => _selectedSemester = s);
                _loadEntries();
              },
            ),
            _FilterDropdown<Programme>(
              label: 'Programme',
              value: _selectedProgramme,
              items: _programmes,
              displayText: (p) => p.code,
              onChanged: (p) {
                setState(() => _selectedProgramme = p);
                _loadGroups();
                _loadEntries();
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reload'),
              onPressed: _loadEntries,
            ),
          ],
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

  Future<void> _showEntryForm(BuildContext context, {TimetableEntry? entry}) async {
    final bool? success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EntryForm(
        entry: entry,
        years: _years,
        allSemesters: _semesters,
        programmes: _programmes,
        allGroups: _groups,
        allCourses: _courses,
        lecturers: _lecturers,
        venues: _venues,
        acService: _acService,
        ttService: _ttService,
        selectedSemesterId: _selectedSemester?.id,
        onSaved: (e) async {
          entry == null
              ? await _ttService.createEntry(e)
              : await _ttService.updateEntry(e);
          if (!ctx.mounted) return;
          Navigator.pop(ctx, true);
        },
        onDelete: entry == null ? null : (e) async {
          await _ttService.deleteEntry(e.id);
          if (ctx.mounted) Navigator.pop(ctx, true);
        },
        savedEntryRef: entry,
      ),
    );

    if (success == true && mounted) {
      _loadEntries();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entry == null ? 'Entry created.' : 'Entry updated.'),
          backgroundColor: AppColors.statusFree,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

// ── Entry form widget (Phase 8 enhanced) ──────────────────────────────────────
class _EntryForm extends StatefulWidget {
  final TimetableEntry? entry;
  final List<AcademicYear> years;
  final List<Semester> allSemesters;
  final List<Programme> programmes;
  final List<StudentGroup> allGroups;
  final List<Course> allCourses;
  final List<Lecturer> lecturers;
  final List<Venue> venues;
  final AcademicsService acService;
  final TimetableService ttService;
  final int? selectedSemesterId;
  final Future<void> Function(TimetableEntry) onSaved;
  final Future<void> Function(TimetableEntry)? onDelete;
  final TimetableEntry? savedEntryRef;

  const _EntryForm({
    this.entry,
    required this.years,
    required this.allSemesters,
    required this.programmes,
    required this.allGroups,
    required this.allCourses,
    required this.lecturers,
    required this.venues,
    required this.acService,
    required this.ttService,
    this.selectedSemesterId,
    required this.onSaved,
    this.onDelete,
    this.savedEntryRef,
  });

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _formKey = GlobalKey<FormState>();
  int? _yearId, _semId, _progId, _groupId, _courseId, _lecturerId, _venueId;
  String _day = 'MONDAY';
  String _startTime = '08:00:00';
  String _endTime = '10:00:00';
  String _status = 'DRAFT';
  bool _saving = false;

  // Phase 8
  int? _expectedStudentCount;
  VenueRecommendationResult? _recommendations;
  bool _loadingRecommendations = false;
  Set<int> _recommendedVenueIds = {};

  static const _days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
  static const _times = [
    '07:00:00', '08:00:00', '09:00:00', '10:00:00', '11:00:00', '12:00:00',
    '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00', '18:00:00',
  ];

  List<Semester> get _visibleSemesters =>
      widget.allSemesters.where((s) => _yearId == null || s.academicYearId == _yearId).toList();

  List<Course> get _visibleCourses =>
      widget.allCourses.where((c) => _progId == null || c.programmeId == _progId).toList();

  List<StudentGroup> get _visibleGroups =>
      widget.allGroups.where((g) => _progId == null || g.programmeId == _progId).toList();

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _yearId = e?.academicYearId ?? (widget.years.isNotEmpty ? widget.years.first.id : null);
    final yearlySems = _visibleSemesters;
    _semId = e?.semesterId ?? (yearlySems.isNotEmpty ? yearlySems.first.id : null);
    _progId = e?.programmeId ?? (widget.programmes.isNotEmpty ? widget.programmes.first.id : null);
    _groupId = e?.studentGroupId;
    final progCourses = _visibleCourses;
    _courseId = e?.courseId ?? (progCourses.isNotEmpty ? progCourses.first.id : null);
    _lecturerId = e?.lecturerId ?? (widget.lecturers.isNotEmpty ? widget.lecturers.first.id : null);
    _venueId = e?.venueId;
    _day = e?.dayOfWeek ?? 'MONDAY';
    _startTime = e?.startTime ?? '08:00:00';
    _endTime = e?.endTime ?? '10:00:00';
    _status = e?.status ?? 'DRAFT';
  }

  String _hm(String t) {
    final parts = t.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  Future<void> _fetchRecommendations() async {
    if (_expectedStudentCount == null || _expectedStudentCount! < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter expected student count first.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    setState(() {
      _loadingRecommendations = true;
      _recommendations = null;
    });
    try {
      final result = await widget.ttService.getVenueRecommendations(
        studentsCount: _expectedStudentCount!,
        dayOfWeek: _day,
        startTime: _startTime,
        endTime: _endTime,
        semesterId: _semId ?? widget.selectedSemesterId,
      );
      if (mounted) {
        setState(() {
          _recommendations = result;
          _recommendedVenueIds = result.recommended.map((v) => v.id).toSet();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to get recommendations: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingRecommendations = false);
    }
  }

  Future<void> _selectVenueWithOverrideCheck(int venueId) async {
    if (_recommendations != null &&
        _recommendations!.hasRecommendations &&
        !_recommendedVenueIds.contains(venueId)) {
      final note = await _showOverrideReasonDialog();
      if (!mounted) return;
      if (note == null) return;
    }
    setState(() => _venueId = venueId);
  }

  Future<String?> _showOverrideReasonDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Venue Override'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This venue was not in the recommendations. Please state the reason for override:'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Override reason...'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_yearId == null || _semId == null || _progId == null ||
        _courseId == null || _lecturerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fill all required fields: Year, Semester, Programme, Course, Lecturer.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final entry = TimetableEntry(
        id: widget.entry?.id ?? 0,
        academicYearId: _yearId!,
        academicYearName: '',
        semesterId: _semId!,
        semesterName: '',
        programmeId: _progId!,
        programmeName: '', programmeCode: '',
        studentGroupId: _groupId,
        studentGroupName: null,
        courseId: _courseId!,
        courseCode: '', courseName: '',
        lecturerId: _lecturerId!,
        lecturerName: '',
        venueId: _venueId,
        venueCode: null, venueName: null,
        dayOfWeek: _day,
        startTime: _startTime,
        endTime: _endTime,
        status: _status,
      );
      await widget.onSaved(entry);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $err'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;
    final semItems = _visibleSemesters;
    final courseItems = _visibleCourses;
    final groupItems = _visibleGroups;

    if (_semId != null && !semItems.any((s) => s.id == _semId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _semId = null);
      });
    }
    if (_courseId != null && !courseItems.any((c) => c.id == _courseId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _courseId = null);
      });
    }
    if (_groupId != null && !groupItems.any((g) => g.id == _groupId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _groupId = null);
      });
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isEdit ? 'Edit Timetable Entry' : 'New Timetable Entry', style: AppTypography.headlineMedium),
            if (isEdit && widget.onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => widget.onDelete!(widget.entry!),
              ),
          ]),
          const SizedBox(height: 20),

          // Academic Year + Semester
          Row(children: [
            Expanded(child: _dd<int?>(
              'Academic Year *', _yearId,
              widget.years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.name))).toList(),
              (v) => setState(() { _yearId = v; _semId = null; }),
            )),
            Expanded(child: _dd<int?>(
              'Semester *', _semId,
              semItems.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              (v) => setState(() => _semId = v),
            )),
          ]),
          const SizedBox(height: 12),

          // Programme + Group
          Row(children: [
            Expanded(child: _dd<int?>(
              'Programme *', _progId,
              widget.programmes.map((p) => DropdownMenuItem(value: p.id, child: Text(p.code))).toList(),
              (v) => setState(() {
                _progId = v;
                _courseId = null;
                _groupId = null;
              }),
            )),
            Expanded(child: _dd<int?>(
              'Student Group', _groupId,
              [
                const DropdownMenuItem(value: null, child: Text('All groups')),
                ...groupItems.map((g) => DropdownMenuItem(value: g.id, child: Text(g.groupName))),
              ],
              (v) => setState(() => _groupId = v),
            )),
          ]),
          const SizedBox(height: 12),

          // Course
          _dd<int?>(
            'Course *', _courseId,
            courseItems.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text('${c.courseCode} — ${c.courseName}', overflow: TextOverflow.ellipsis),
            )).toList(),
            (v) => setState(() => _courseId = v),
          ),
          const SizedBox(height: 12),

          // Lecturer
          _dd<int?>(
            'Lecturer *', _lecturerId,
            widget.lecturers.map((l) => DropdownMenuItem(
              value: l.id, child: Text(l.fullName, overflow: TextOverflow.ellipsis),
            )).toList(),
            (v) => setState(() => _lecturerId = v),
          ),
          const SizedBox(height: 12),

          // Day
          _dd<String>(
            'Day of Week', _day,
            _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            (v) => setState(() { _day = v!; _recommendations = null; }),
          ),
          const SizedBox(height: 12),

          // Start + End time
          Row(children: [
            Expanded(child: _dd<String>(
              'Start Time', _startTime,
              _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
              (v) => setState(() { _startTime = v!; _recommendations = null; }),
            )),
            Expanded(child: _dd<String>(
              'End Time', _endTime,
              _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(),
              (v) => setState(() { _endTime = v!; _recommendations = null; }),
            )),
          ]),
          const SizedBox(height: 16),

          // ── Phase 8: Venue Recommendations section ─────────────────────────
          const Divider(),
          Text('Venue Recommendations', style: AppTypography.titleMedium.copyWith(color: AppColors.accent)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Expected Student Count',
                  hintText: 'e.g. 40',
                ),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  setState(() {
                    _expectedStudentCount = n;
                    _recommendations = null;
                  });
                },
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              icon: _loadingRecommendations
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.textOnPrimary, strokeWidth: 2))
                  : const Icon(Icons.search, color: AppColors.textOnPrimary),
              label: const Text('Find Venues',
                  style: TextStyle(color: AppColors.textOnPrimary)),
              onPressed: _loadingRecommendations ? null : _fetchRecommendations,
            ),
          ]),
          const SizedBox(height: 8),

          // Recommendation results
          if (_recommendations != null) ...[
            if (_recommendations!.hasRecommendations) ...[
              Text('Recommended venues:',
                  style: AppTypography.labelMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              ..._recommendations!.recommended.map((rec) => _VenueRecommendationCard(
                rec: rec,
                isSelected: _venueId == rec.id,
                onSelect: () => setState(() => _venueId = rec.id),
              )),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withAlpha(60)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_outlined, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recommendations!.notFoundReason ?? 'No venues found.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 4),
          ],

          // Manual venue dropdown (fallback/override)
          _dd<int?>(
            'Venue (manual override)', _venueId,
            [
              const DropdownMenuItem(value: null, child: Text('No venue')),
              ...widget.venues.map((v) => DropdownMenuItem(value: v.id, child: Text(v.code))),
            ],
            (v) async {
              if (v != null) {
                await _selectVenueWithOverrideCheck(v);
              } else {
                setState(() => _venueId = null);
              }
            },
          ),
          const SizedBox(height: 12),

          // Status
          _dd<String>(
            'Status', _status,
            ['DRAFT', 'PUBLISHED', 'VALIDATED'].map((s) =>
              DropdownMenuItem(value: s, child: Text(s))).toList(),
            (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          color: AppColors.textOnPrimary, strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save Changes' : 'Create Entry'),
            ),
          ),
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

// ── Venue Recommendation Card ─────────────────────────────────────────────────

class _VenueRecommendationCard extends StatelessWidget {
  final VenueRecommendation rec;
  final bool isSelected;
  final VoidCallback onSelect;

  const _VenueRecommendationCard({
    required this.rec,
    required this.isSelected,
    required this.onSelect,
  });

  Color get _fitColor {
    if (rec.fitLabel == 'Best fit') return AppColors.statusFree;
    if (rec.fitLabel == 'Good fit') return AppColors.accent;
    return AppColors.statusInUse;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withAlpha(20) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.inputBorder,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${rec.code} — ${rec.name}',
                style: AppTypography.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _fitColor.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(rec.fitLabel,
                  style: AppTypography.labelMedium.copyWith(color: _fitColor)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(rec.buildingName, style: AppTypography.bodySmall),
            const SizedBox(width: 12),
            const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${rec.capacity} seats (${rec.utilizationPct}%)',
                style: AppTypography.bodySmall),
          ]),
          if (rec.resources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: rec.resources
                  .take(4)
                  .map((r) => Chip(
                        label: Text(r.toString(),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: AppColors.background,
                        side: const BorderSide(color: AppColors.inputBorder),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isSelected ? null : onSelect,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              child: Text(isSelected ? 'Selected' : 'Select'),
            ),
          ),
        ]),
      ),
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
