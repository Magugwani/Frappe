import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class AcademicYearScreen extends StatefulWidget {
  const AcademicYearScreen({super.key});
  @override
  State<AcademicYearScreen> createState() => _AcademicYearScreenState();
}

class _AcademicYearScreenState extends State<AcademicYearScreen> {
  final _service = AcademicsService();
  List<AcademicYear> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await _service.getYears();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('Academic Years'),
      ),  
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.textOnPrimary),
        onPressed: () => _showForm(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const Center(child: Text('No academic years yet. Tap + to add.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildTile(_items[i]),
                    ),
            ),
    );
  }

  Widget _buildTile(AcademicYear y) {
    final statusColor = {
      'ACTIVE': AppColors.statusFree,
      'INACTIVE': AppColors.textSecondary,
      'COMPLETED': AppColors.statusBooked,
    }[y.status] ?? AppColors.textSecondary;

    return ManagementTile(
      title: y.name,
      subtitle: '${y.startDate} → ${y.endDate}',
      badge: y.status,
      badgeColor: statusColor,
      icon: Icons.calendar_today_outlined,
      iconColor: AppColors.primary,
      onEdit: () => _showForm(context, year: y),
      onDelete: () => _delete(y),
    );
  }

  Future<void> _delete(AcademicYear y) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Academic Year'),
        content: Text('Delete "${y.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _service.deleteYear(y.id);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  void _showForm(BuildContext context, {AcademicYear? year}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AcademicYearForm(
        year: year,
        onSaved: (y) async {
          Navigator.pop(ctx);
          try {
            year == null ? await _service.createYear(y) : await _service.updateYear(y);
            _load();
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
          }
        },
      ),
    );
  }
}

class _AcademicYearForm extends StatefulWidget {
  final AcademicYear? year;
  final Future<void> Function(AcademicYear) onSaved;
  const _AcademicYearForm({this.year, required this.onSaved});
  @override
  State<_AcademicYearForm> createState() => _AcademicYearFormState();
}

class _AcademicYearFormState extends State<_AcademicYearForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _start;
  late final TextEditingController _end;
  String _status = 'INACTIVE';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.year?.name ?? '');
    _start = TextEditingController(text: widget.year?.startDate ?? '');
    _end = TextEditingController(text: widget.year?.endDate ?? '');
    _status = widget.year?.status ?? 'INACTIVE';
  }

  @override
  void dispose() { _name.dispose(); _start.dispose(); _end.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final y = AcademicYear(id: widget.year?.id ?? 0, name: _name.text.trim(), startDate: _start.text.trim(), endDate: _end.text.trim(), status: _status);
    await widget.onSaved(y);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.year == null ? 'New Academic Year' : 'Edit Academic Year', style: AppTypography.headlineMedium),
            const SizedBox(height: 20),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name (e.g. 2026/2027)'), validator: (v) => v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _start, decoration: const InputDecoration(labelText: 'Start Date (YYYY-MM-DD)'), validator: (v) => v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _end, decoration: const InputDecoration(labelText: 'End Date (YYYY-MM-DD)'), validator: (v) => v!.isEmpty ? 'Required' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['INACTIVE', 'ACTIVE', 'COMPLETED'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator(color: AppColors.textOnPrimary) : Text(widget.year == null ? 'Create' : 'Save Changes'))),
          ],
        ),
      ),
    );
  }
}
