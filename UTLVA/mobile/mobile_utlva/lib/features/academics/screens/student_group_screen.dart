import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class StudentGroupScreen extends StatefulWidget {
  const StudentGroupScreen({super.key});
  @override
  State<StudentGroupScreen> createState() => _StudentGroupScreenState();
}

class _StudentGroupScreenState extends State<StudentGroupScreen> {
  final _service = AcademicsService();
  List<StudentGroup> _items = [];
  List<Programme> _programmes = [];
  List<AcademicYear> _years = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_service.getGroups(), _service.getProgrammes(), _service.getYears()]);
      _items = r[0] as List<StudentGroup>;
      _programmes = r[1] as List<Programme>;
      _years = r[2] as List<AcademicYear>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Student Groups')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No student groups yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final g = _items[i];
                    return ReusableCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.statusBooked.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.group_outlined, color: AppColors.statusBooked, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(g.displayName, style: AppTypography.titleMedium),
                          Text('${g.programmeCode} — Year ${g.yearOfStudy}', style: AppTypography.bodySmall),
                          if (g.academicYearName != null)
                            Text('${g.academicYearName}', style: AppTypography.caption.copyWith(color: AppColors.accent)),
                        ])),
                        // Student count badge
                        Column(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: g.studentCount > 0 ? AppColors.primary.withAlpha(20) : AppColors.divider,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${g.studentCount} students',
                              style: AppTypography.caption.copyWith(
                                color: g.studentCount > 0 ? AppColors.primary : AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 16), color: AppColors.primary, onPressed: () => _showForm(context, group: g), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 16), color: AppColors.error, onPressed: () => _delete(g), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
                          ]),
                        ]),
                      ]),
                    );
                  })),
    );
  }

  Future<void> _delete(StudentGroup g) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Group'), content: Text('Delete "${g.displayName}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteGroup(g.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {StudentGroup? group}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GroupForm(
        group: group, programmes: _programmes, years: _years,
        onSaved: (g) async {
          Navigator.pop(ctx);
          try { group == null ? await _service.createGroup(g) : await _service.updateGroup(g); _load(); }
          catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); }
        },
      ));
  }
}

class _GroupForm extends StatefulWidget {
  final StudentGroup? group;
  final List<Programme> programmes;
  final List<AcademicYear> years;
  final Future<void> Function(StudentGroup) onSaved;
  const _GroupForm({this.group, required this.programmes, required this.years, required this.onSaved});
  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _groupName, _countCtrl;
  int? _progId, _yearId;
  int _year = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupName = TextEditingController(text: widget.group?.groupName ?? '');
    _countCtrl = TextEditingController(text: widget.group?.studentCount.toString() ?? '0');
    _progId = widget.group?.programmeId ?? (widget.programmes.isNotEmpty ? widget.programmes.first.id : null);
    _yearId = widget.group?.academicYearId ?? (widget.years.isNotEmpty ? widget.years.first.id : null);
    _year = widget.group?.yearOfStudy ?? 1;
  }

  @override
  void dispose() { _groupName.dispose(); _countCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _progId == null) return;
    setState(() => _saving = true);
    await widget.onSaved(StudentGroup(
      id: widget.group?.id ?? 0,
      programmeId: _progId!,
      programmeName: '', programmeCode: '',
      academicYearId: _yearId,
      yearOfStudy: _year,
      groupName: _groupName.text.trim(),
      studentCount: int.tryParse(_countCtrl.text) ?? 0,
      displayName: '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final maxYear = widget.programmes.firstWhere((p) => p.id == _progId,
        orElse: () => Programme(id: 0, departmentId: 0, departmentName: '', departmentCode: '', name: '', code: '', durationYears: 4)).durationYears;

    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.group == null ? 'New Student Group' : 'Edit Group', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(value: _yearId, decoration: const InputDecoration(labelText: 'Academic Year'), items: widget.years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.name))).toList(), onChanged: (v) => setState(() => _yearId = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _progId, decoration: const InputDecoration(labelText: 'Programme'), items: widget.programmes.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(), onChanged: (v) => setState(() { _progId = v; _year = 1; }), validator: (v) => v == null ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _year.clamp(1, maxYear), decoration: const InputDecoration(labelText: 'Year of Study'), items: List.generate(maxYear, (i) => DropdownMenuItem(value: i + 1, child: Text('Year ${i + 1}'))).toList(), onChanged: (v) => setState(() => _year = v!)),
        const SizedBox(height: 12),
        TextFormField(controller: _groupName, decoration: const InputDecoration(labelText: 'Group Name (e.g. Group A)'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(
          controller: _countCtrl,
          decoration: const InputDecoration(
            labelText: 'Expected Student Count',
            hintText: 'e.g. 45',
            helperText: 'Used for venue capacity matching during timetable generation.',
          ),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            if (int.tryParse(v) == null) return 'Enter a valid number';
            return null;
          },
        ),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.group == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
