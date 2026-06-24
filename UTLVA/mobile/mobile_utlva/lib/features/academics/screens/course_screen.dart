import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key});
  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  final _service = AcademicsService();
  List<Course> _items = [];
  List<Programme> _programmes = [];
  List<Semester> _semesters = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_service.getCourses(), _service.getProgrammes(), _service.getSemesters()]);
      _items = r[0] as List<Course>;
      _programmes = r[1] as List<Programme>;
      _semesters = r[2] as List<Semester>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Courses')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No courses yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = _items[i];
                    return ManagementTile(
                      title: '${c.courseCode} — ${c.courseName}',
                      subtitle: '${c.programmeName} | Year ${c.yearOfStudy} | ${c.creditHours} credits | ${c.weeklyHours}h/wk',
                      badge: c.requiredVenueType.isEmpty ? 'Any' : c.requiredVenueType,
                      badgeColor: AppColors.statusInUse,
                      icon: Icons.menu_book_outlined, iconColor: AppColors.statusInUse,
                      onEdit: () => _showForm(context, course: c),
                      onDelete: () => _delete(c),
                    );
                  })),
    );
  }

  Future<void> _delete(Course c) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Course'), content: Text('Delete "${c.courseName}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteCourse(c.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {Course? course}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CourseForm(course: course, programmes: _programmes, semesters: _semesters, onSaved: (c) async { Navigator.pop(ctx); try { course == null ? await _service.createCourse(c) : await _service.updateCourse(c); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }));
  }
}

class _CourseForm extends StatefulWidget {
  final Course? course;
  final List<Programme> programmes;
  final List<Semester> semesters;
  final Future<void> Function(Course) onSaved;
  const _CourseForm({this.course, required this.programmes, required this.semesters, required this.onSaved});
  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code, _name;
  int? _progId, _semId;
  int _year = 1, _credits = 3, _weekly = 3;
  String _venueType = '';
  final Set<String> _resources = {};
  bool _saving = false;

  static const _venueTypes = ['', 'CLASSROOM', 'LECTURE_HALL', 'COMPUTER_LAB', 'LABORATORY', 'SEMINAR_ROOM', 'AUDITORIUM'];
  // Standard resource options — used by generator for venue matching
  static const _resourceOptions = [
    ('projector', 'Projector'),
    ('computer', 'Computers'),
    ('laboratory_equipment', 'Lab Equipment'),
    ('audio_system', 'Audio System'),
    ('whiteboard', 'Whiteboard'),
    ('air_conditioning', 'Air Conditioning'),
  ];

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.course?.courseCode ?? '');
    _name = TextEditingController(text: widget.course?.courseName ?? '');
    _progId = widget.course?.programmeId ?? (widget.programmes.isNotEmpty ? widget.programmes.first.id : null);
    _semId = widget.course?.semesterId;
    _year = widget.course?.yearOfStudy ?? 1;
    _credits = widget.course?.creditHours ?? 3;
    _weekly = widget.course?.weeklyHours ?? 3;
    _venueType = widget.course?.requiredVenueType ?? '';
    // Load existing resources from JSON list
    if (widget.course != null) {
      for (final r in widget.course!.requiredResources) {
        _resources.add(r.toString());
      }
    }
  }

  @override
  void dispose() { _code.dispose(); _name.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _progId == null) return;
    setState(() => _saving = true);
    await widget.onSaved(Course(
      id: widget.course?.id ?? 0,
      courseCode: _code.text.trim(),
      courseName: _name.text.trim(),
      programmeId: _progId!,
      programmeName: '',
      semesterId: _semId,
      yearOfStudy: _year,
      creditHours: _credits,
      weeklyHours: _weekly,
      requiredVenueType: _venueType,
      requiredResources: _resources.toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.course == null ? 'New Course' : 'Edit Course', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Course Code (e.g. BIT201)'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Course Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _progId, decoration: const InputDecoration(labelText: 'Programme'), items: widget.programmes.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _progId = v), validator: (v) => v == null ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(value: _semId, decoration: const InputDecoration(labelText: 'Semester (optional)'), items: [const DropdownMenuItem(value: null, child: Text('None')), ...widget.semesters.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))], onChanged: (v) => setState(() => _semId = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(value: _year, decoration: const InputDecoration(labelText: 'Year'), items: [1,2,3,4,5].map((n) => DropdownMenuItem(value: n, child: Text('Year $n'))).toList(), onChanged: (v) => setState(() => _year = v!))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(value: _credits, decoration: const InputDecoration(labelText: 'Credits'), items: [1,2,3,4,5,6].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(), onChanged: (v) => setState(() => _credits = v!))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(value: _weekly, decoration: const InputDecoration(labelText: 'Hrs/wk'), items: [1,2,3,4,5,6].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(), onChanged: (v) => setState(() => _weekly = v!))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _venueType,
          decoration: const InputDecoration(labelText: 'Required Venue Type'),
          items: _venueTypes.map((t) => DropdownMenuItem(value: t, child: Text(t.isEmpty ? 'Any type' : t.replaceAll('_', ' ')))).toList(),
          onChanged: (v) => setState(() => _venueType = v ?? ''),
        ),
        const SizedBox(height: 16),
        // Resources checklist — used by generator to match venue resources
        Text('Required Resources', style: AppTypography.titleMedium),
        Text('Generator selects venues that have all checked resources.', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _resourceOptions.map((opt) {
            final key = opt.$1;
            final label = opt.$2;
            final selected = _resources.contains(key);
            return FilterChip(
              label: Text(label, style: AppTypography.labelMedium.copyWith(color: selected ? AppColors.textOnPrimary : AppColors.textMain)),
              selected: selected,
              selectedColor: AppColors.primary,
              checkmarkColor: AppColors.textOnPrimary,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: selected ? AppColors.primary : AppColors.inputBorder),
              onSelected: (v) => setState(() { if (v) _resources.add(key); else _resources.remove(key); }),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.course == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
