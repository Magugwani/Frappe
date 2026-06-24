import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class SemesterScreen extends StatefulWidget {
  const SemesterScreen({super.key});
  @override
  State<SemesterScreen> createState() => _SemesterScreenState();
}

class _SemesterScreenState extends State<SemesterScreen> {
  final _service = AcademicsService();
  List<Semester> _items = [];
  List<AcademicYear> _years = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([_service.getSemesters(), _service.getYears()]);
      _items = results[0] as List<Semester>;
      _years = results[1] as List<AcademicYear>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Semesters')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No semesters yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildTile(_items[i]))),
    );
  }

  Widget _buildTile(Semester s) => ManagementTile(
    title: s.name,
    subtitle: '${s.academicYearName} | ${s.startDate} → ${s.endDate}',
    icon: Icons.date_range_outlined, iconColor: AppColors.accent,
    onEdit: () => _showForm(context, semester: s),
    onDelete: () async {
      final confirm = await _confirmDelete(context);
      if (confirm == true) { try { await _service.deleteSemester(s.id); _load(); } catch (e) { _showError(e); } }
    },
  );

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Semester'),
      content: const Text('Are you sure?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    ),
  );

  void _showError(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
  }

  void _showForm(BuildContext context, {Semester? semester}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SemesterForm(
        semester: semester, years: _years,
        onSaved: (s) async {
          Navigator.pop(ctx);
          try { semester == null ? await _service.createSemester(s) : await _service.updateSemester(s); _load(); }
          catch (e) { _showError(e); }
        },
      ),
    );
  }
}

class _SemesterForm extends StatefulWidget {
  final Semester? semester;
  final List<AcademicYear> years;
  final Future<void> Function(Semester) onSaved;
  const _SemesterForm({this.semester, required this.years, required this.onSaved});
  @override
  State<_SemesterForm> createState() => _SemesterFormState();
}

class _SemesterFormState extends State<_SemesterForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _start, _end;
  int? _yearId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.semester?.name ?? '');
    _start = TextEditingController(text: widget.semester?.startDate ?? '');
    _end = TextEditingController(text: widget.semester?.endDate ?? '');
    _yearId = widget.semester?.academicYearId ?? (widget.years.isNotEmpty ? widget.years.first.id : null);
  }

  @override
  void dispose() { _name.dispose(); _start.dispose(); _end.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _yearId == null) return;
    setState(() => _saving = true);
    await widget.onSaved(Semester(id: widget.semester?.id ?? 0, academicYearId: _yearId!, academicYearName: '', name: _name.text.trim(), startDate: _start.text.trim(), endDate: _end.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.semester == null ? 'New Semester' : 'Edit Semester', style: AppTypography.headlineMedium),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            value: _yearId,
            decoration: const InputDecoration(labelText: 'Academic Year'),
            items: widget.years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.name))).toList(),
            onChanged: (v) => setState(() => _yearId = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Semester Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _start, decoration: const InputDecoration(labelText: 'Start Date (YYYY-MM-DD)'), validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _end, decoration: const InputDecoration(labelText: 'End Date (YYYY-MM-DD)'), validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.semester == null ? 'Create' : 'Save'))),
        ]),
      ),
    );
  }
}
