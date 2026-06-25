import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../core/widgets/timetable_grid_view.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/models/student_profile.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';

class StudentTimetableScreen extends StatefulWidget {
  const StudentTimetableScreen({super.key});
  @override
  State<StudentTimetableScreen> createState() => _StudentTimetableScreenState();
}

class _StudentTimetableScreenState extends State<StudentTimetableScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  // Reference data for manual fallback selection
  List<Programme> _programmes = [];
  List<StudentGroup> _groups = [];
  List<Semester> _semesters = [];

  // Auto-detected from StudentProfile
  StudentProfile? _profile;
  bool _profileLoaded = false;

  // Active filter selections
  int? _selectedProgrammeId;
  String? _selectedProgrammeName;
  int? _selectedGroupId;
  String? _selectedGroupName;
  Semester? _selectedSemester;

  List<TimetableEntry> _entries = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Load profile and reference data in parallel, then auto-load timetable
  /// if the profile has a complete programme assignment.
  Future<void> _bootstrap() async {
    final results = await Future.wait([
      _acService.getMyStudentProfile(),
      _acService.getProgrammes(),
      _acService.getSemesters(),
    ]);

    _profile = results[0] as StudentProfile?;
    _programmes = results[1] as List<Programme>;
    _semesters = results[2] as List<Semester>;

    if (mounted) {
      setState(() {
        _profileLoaded = true;
        if (_semesters.isNotEmpty) _selectedSemester = _semesters.first;

        if (_profile != null && _profile!.isComplete) {
          // Auto-populate from profile
          _selectedProgrammeId = _profile!.programmeId;
          _selectedProgrammeName = _profile!.programmeName;
          _selectedGroupId = _profile!.studentGroupId;
          _selectedGroupName = _profile!.studentGroupName;
        }
      });

      if (_profile != null && _profile!.isComplete) {
        // Load groups for the profile's programme, then fetch timetable
        await _loadGroupsForProgramme(_profile!.programmeId!);
        await _fetchTimetable();
      }
    }
  }

  Future<void> _loadGroupsForProgramme(int programmeId) async {
    final groups = await _acService.getGroups(programmeId: programmeId);
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _fetchTimetable() async {
    if (_selectedProgrammeId == null) return;
    if (!mounted) return;
    setState(() { _loading = true; _searched = true; });
    try {
      final entries = await _ttService.getStudentTimetable(
        programmeId: _selectedProgrammeId!,
        studentGroupId: _selectedGroupId,
        semesterId: _selectedSemester?.id,
      );
      if (mounted) setState(() => _entries = entries);
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
      appBar: CustomAppBar(title: 'My Class Timetable'),
      body: !_profileLoaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                _buildFilterPanel(),
                const Divider(height: 1),
                Expanded(child: _buildBody()),
              ],
            ),
    );
  }

  // ── Filter / selection panel ───────────────────────────────────────────────

  Widget _buildFilterPanel() {
    return ReusableCard(
      borderRadius: 0,
      elevation: 2,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile status banner
          if (_profile != null && _profile!.isComplete)
            _buildProfileBanner()
          else
            _buildNoProfileBanner(),
          const SizedBox(height: 12),

          // Programme + Group selectors
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedProgrammeId,
                decoration: const InputDecoration(labelText: 'Programme', isDense: true),
                items: _programmes
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.code)))
                    .toList(),
                onChanged: (id) async {
                  final prog = _programmes.firstWhere((p) => p.id == id);
                  setState(() {
                    _selectedProgrammeId = id;
                    _selectedProgrammeName = prog.name;
                    _selectedGroupId = null;
                    _selectedGroupName = null;
                    _groups = [];
                  });
                  if (id != null) await _loadGroupsForProgramme(id);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _selectedGroupId,
                decoration: const InputDecoration(labelText: 'Group', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All groups')),
                  ..._groups.map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.groupName),
                      )),
                ],
                onChanged: (id) {
                  final g = id != null
                      ? _groups.firstWhere((g) => g.id == id)
                      : null;
                  setState(() {
                    _selectedGroupId = id;
                    _selectedGroupName = g?.groupName;
                  });
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Semester + View button
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<Semester>(
                value: _selectedSemester,
                decoration: const InputDecoration(labelText: 'Semester', isDense: true),
                items: _semesters
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (s) => setState(() => _selectedSemester = s),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _fetchTimetable,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('View'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildProfileBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.statusFree.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.statusFree.withAlpha(60)),
      ),
      child: Row(children: [
        const Icon(Icons.person_outline, size: 16, color: AppColors.statusFree),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Profile: ${_profile!.programmeName ?? ''}'
            '${_profile!.studentGroupName != null ? ' · ${_profile!.studentGroupName}' : ''}',
            style: AppTypography.labelMedium.copyWith(color: AppColors.statusFree),
          ),
        ),
        GestureDetector(
          onTap: () => _showProfileSetup(prefill: _profile),
          child: Text('Edit', style: AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildNoProfileBanner() {
    return GestureDetector(
      onTap: () => _showProfileSetup(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.statusInUse.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.statusInUse.withAlpha(60)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.statusInUse),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Set up your student profile to auto-load your timetable.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.statusInUse),
            ),
          ),
          Text('Setup →', style: AppTypography.caption.copyWith(color: AppColors.statusInUse, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ── Timetable body ────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (!_searched) {
      return _buildPrompt();
    }
    if (_entries.isEmpty) {
      return _buildEmpty();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          // Dynamic time range derived from entries — no fixed 07:00–19:00
          TimetableGridView(
            entries: _entries,
            showOnlyDaysWithEntries: false,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final prog = _selectedProgrammeName ?? '';
    final group = _selectedGroupName != null ? ' — $_selectedGroupName' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$prog$group',
            style: AppTypography.titleLarge.copyWith(color: AppColors.primary)),
        Text(
          '${_selectedSemester?.name ?? ''} | ${_entries.length} published sessions',
          style: AppTypography.bodySmall,
        ),
      ],
    );
  }

  Widget _buildPrompt() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('Select your programme and group above',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('then tap View to load your timetable.', style: AppTypography.bodySmall),
        ]),
      );

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_busy, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('No published timetable found',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Your timetable may not be published yet.', style: AppTypography.bodySmall),
        ]),
      );

  // ── Profile setup sheet ───────────────────────────────────────────────────

  void _showProfileSetup({StudentProfile? prefill}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ProfileSetupSheet(
        prefill: prefill,
        programmes: _programmes,
        onSaved: (regNum, progId, groupId) async {
          Navigator.pop(ctx);
          try {
            // Determine user ID from existing profile or create new
            final prog = _programmes.firstWhere((p) => p.id == progId);
            if (prefill != null) {
              final updated = StudentProfile(
                id: prefill.id,
                userId: prefill.userId,
                fullName: prefill.fullName,
                email: prefill.email,
                registrationNumber: regNum,
                programmeId: progId,
                programmeName: prog.name,
                programmeCode: prog.code,
                studentGroupId: groupId,
              );
              await _acService.updateStudentProfile(updated);
            } else {
              // For new profile, user ID comes from auth — server resolves it
              // We pass user=0 as placeholder; the server uses request.user
              final newProfile = StudentProfile(
                id: 0, userId: 0, fullName: '', email: '',
                registrationNumber: regNum,
                programmeId: progId,
                studentGroupId: groupId,
              );
              await _acService.createStudentProfile(newProfile);
            }
            await _bootstrap();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
              );
            }
          }
        },
      ),
    );
  }
}

// ── Profile setup form ────────────────────────────────────────────────────────

class _ProfileSetupSheet extends StatefulWidget {
  final StudentProfile? prefill;
  final List<Programme> programmes;
  final void Function(String regNum, int programmeId, int? groupId) onSaved;

  const _ProfileSetupSheet({
    this.prefill,
    required this.programmes,
    required this.onSaved,
  });

  @override
  State<_ProfileSetupSheet> createState() => _ProfileSetupSheetState();
}

class _ProfileSetupSheetState extends State<_ProfileSetupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _acService = AcademicsService();

  late final TextEditingController _regNumCtrl;
  int? _programmeId;
  int? _groupId;
  List<StudentGroup> _groups = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _regNumCtrl = TextEditingController(text: widget.prefill?.registrationNumber ?? '');
    _programmeId = widget.prefill?.programmeId ?? (widget.programmes.isNotEmpty ? widget.programmes.first.id : null);
    _groupId = widget.prefill?.studentGroupId;
    if (_programmeId != null) _loadGroups(_programmeId!);
  }

  @override
  void dispose() { _regNumCtrl.dispose(); super.dispose(); }

  Future<void> _loadGroups(int progId) async {
    final g = await _acService.getGroups(programmeId: progId);
    if (mounted) setState(() { _groups = g; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Student Profile Setup', style: AppTypography.headlineMedium),
          const SizedBox(height: 4),
          Text('This lets the app load your timetable automatically.', style: AppTypography.bodySmall),
          const SizedBox(height: 20),
          TextFormField(
            controller: _regNumCtrl,
            decoration: const InputDecoration(labelText: 'Registration Number'),
            validator: (v) => v!.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _programmeId,
            decoration: const InputDecoration(labelText: 'Programme'),
            items: widget.programmes.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (id) { setState(() { _programmeId = id; _groupId = null; _groups = []; }); if (id != null) _loadGroups(id); },
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _groupId,
            decoration: const InputDecoration(labelText: 'Student Group (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Not specified')),
              ..._groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.groupName))),
            ],
            onChanged: (id) => setState(() => _groupId = id),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : () async {
                if (!_formKey.currentState!.validate() || _programmeId == null) return;
                setState(() => _saving = true);
                widget.onSaved(_regNumCtrl.text.trim(), _programmeId!, _groupId);
              },
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2))
                  : const Text('Save Profile'),
            ),
          ),
        ]),
      ),
    );
  }
}
