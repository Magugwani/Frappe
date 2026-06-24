import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class ProgrammeScreen extends StatefulWidget {
  const ProgrammeScreen({super.key});
  @override
  State<ProgrammeScreen> createState() => _ProgrammeScreenState();
}

class _ProgrammeScreenState extends State<ProgrammeScreen> {
  final _service = AcademicsService();
  List<Programme> _items = [];
  List<Department> _departments = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_service.getProgrammes(), _service.getDepartments()]);
      _items = r[0] as List<Programme>;
      _departments = r[1] as List<Department>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Programmes')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No programmes yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _items[i];
                    return ManagementTile(
                      title: p.name, subtitle: '${p.departmentCode} — ${p.departmentName}',
                      badge: '${p.durationYears} yrs', badgeColor: AppColors.accent,
                      icon: Icons.school_outlined, iconColor: AppColors.accent,
                      onEdit: () => _showForm(context, prog: p),
                      onDelete: () => _delete(p),
                    );
                  })),
    );
  }

  Future<void> _delete(Programme p) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Programme'), content: Text('Delete "${p.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteProgramme(p.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {Programme? prog}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ProgrammeForm(prog: prog, departments: _departments, onSaved: (p) async { Navigator.pop(ctx); try { prog == null ? await _service.createProgramme(p) : await _service.updateProgramme(p); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }));
  }
}

class _ProgrammeForm extends StatefulWidget {
  final Programme? prog;
  final List<Department> departments;
  final Future<void> Function(Programme) onSaved;
  const _ProgrammeForm({this.prog, required this.departments, required this.onSaved});
  @override
  State<_ProgrammeForm> createState() => _ProgrammeFormState();
}

class _ProgrammeFormState extends State<_ProgrammeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _code;
  int? _deptId;
  int _duration = 3;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prog?.name ?? '');
    _code = TextEditingController(text: widget.prog?.code ?? '');
    _deptId = widget.prog?.departmentId ?? (widget.departments.isNotEmpty ? widget.departments.first.id : null);
    _duration = widget.prog?.durationYears ?? 3;
  }

  @override
  void dispose() { _name.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _deptId == null) return;
    setState(() => _saving = true);
    await widget.onSaved(Programme(id: widget.prog?.id ?? 0, departmentId: _deptId!, departmentName: '', departmentCode: '', name: _name.text.trim(), code: _code.text.trim().toUpperCase(), durationYears: _duration));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.prog == null ? 'New Programme' : 'Edit Programme', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(value: _deptId, decoration: const InputDecoration(labelText: 'Department'), items: widget.departments.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(), onChanged: (v) => setState(() => _deptId = v), validator: (v) => v == null ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Programme Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Code (e.g. BIT)'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _duration, decoration: const InputDecoration(labelText: 'Duration (years)'), items: [1, 2, 3, 4, 5].map((n) => DropdownMenuItem(value: n, child: Text('$n year${n > 1 ? 's' : ''}'))).toList(), onChanged: (v) => setState(() => _duration = v!)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.prog == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
