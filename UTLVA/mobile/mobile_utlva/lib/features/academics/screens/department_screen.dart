import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen({super.key});
  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen> {
  final _service = AcademicsService();
  List<Department> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _items = await _service.getDepartments(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Departments')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No departments yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => ManagementTile(
                    title: _items[i].name, subtitle: 'Code: ${_items[i].code}',
                    badge: _items[i].code, badgeColor: AppColors.primary,
                    icon: Icons.business_outlined, iconColor: AppColors.primary,
                    onEdit: () => _showForm(context, dept: _items[i]),
                    onDelete: () => _delete(_items[i]),
                  ))),
    );
  }

  Future<void> _delete(Department d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Department'), content: Text('Delete "${d.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteDepartment(d.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {Department? dept}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DeptForm(dept: dept, onSaved: (d) async { Navigator.pop(ctx); try { dept == null ? await _service.createDepartment(d) : await _service.updateDepartment(d); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }));
  }
}

class _DeptForm extends StatefulWidget {
  final Department? dept;
  final Future<void> Function(Department) onSaved;
  const _DeptForm({this.dept, required this.onSaved});
  @override
  State<_DeptForm> createState() => _DeptFormState();
}

class _DeptFormState extends State<_DeptForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _code;
  bool _saving = false;

  @override
  void initState() { super.initState(); _name = TextEditingController(text: widget.dept?.name ?? ''); _code = TextEditingController(text: widget.dept?.code ?? ''); }
  @override
  void dispose() { _name.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.onSaved(Department(id: widget.dept?.id ?? 0, name: _name.text.trim(), code: _code.text.trim().toUpperCase()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.dept == null ? 'New Department' : 'Edit Department', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Department Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Code (e.g. CCT)'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.dept == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
