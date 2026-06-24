import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class TeachingPeriodScreen extends StatefulWidget {
  const TeachingPeriodScreen({super.key});
  @override
  State<TeachingPeriodScreen> createState() => _TeachingPeriodScreenState();
}

class _TeachingPeriodScreenState extends State<TeachingPeriodScreen> {
  final _service = AcademicsService();

  List<TeachingPeriod> _periods = [];
  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];

  AcademicYear? _selectedYear;
  Semester? _selectedSemester;
  bool _loading = true;

  static const _days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
  static const _dayColors = {
    'MONDAY': AppColors.primary,
    'TUESDAY': AppColors.accent,
    'WEDNESDAY': Color(0xFF7B1FA2),
    'THURSDAY': AppColors.statusInUse,
    'FRIDAY': AppColors.statusFree,
    'SATURDAY': Color(0xFF795548),
  };

  @override
  void initState() { super.initState(); _loadRef(); }

  Future<void> _loadRef() async {
    try {
      final r = await Future.wait([_service.getYears(), _service.getSemesters()]);
      _years = r[0] as List<AcademicYear>;
      _semesters = r[1] as List<Semester>;
      // Default to active year and its first semester
      _selectedYear = _years.firstWhere((y) => y.isActive, orElse: () => _years.isNotEmpty ? _years.first : _years.first);
      if (_semesters.isNotEmpty) {
        _selectedSemester = _semesters.firstWhere(
            (s) => s.academicYearId == _selectedYear?.id,
            orElse: () => _semesters.first);
      }
    } catch (_) {}
    if (mounted) { setState(() {}); await _loadPeriods(); }
  }

  Future<void> _loadPeriods() async {
    setState(() => _loading = true);
    try {
      _periods = await _service.getTeachingPeriods(semesterId: _selectedSemester?.id);
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
        title: const Text('Teaching Periods'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.auto_fix_high, color: AppColors.textOnPrimary, size: 18),
            label: const Text('Bulk Add', style: TextStyle(color: AppColors.textOnPrimary)),
            onPressed: () => _showBulkAdd(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: AppColors.textOnPrimary),
        onPressed: () => _showForm(context),
      ),
      body: Column(children: [
        _buildFilters(),
        const Divider(height: 1),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _periods.isEmpty
                ? _buildEmpty()
                : _buildGrid()),
      ]),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dd<AcademicYear?>(
            'Year', _selectedYear, _years,
            (y) => y?.name ?? 'Select year',
            (y) { setState(() { _selectedYear = y; _selectedSemester = null; }); _loadPeriods(); },
          ),
          const SizedBox(width: 10),
          _dd<Semester?>(
            'Semester',
            _selectedSemester,
            _semesters.where((s) => _selectedYear == null || s.academicYearId == _selectedYear!.id).toList(),
            (s) => s?.name ?? 'Select semester',
            (s) { setState(() => _selectedSemester = s); _loadPeriods(); },
          ),
          const SizedBox(width: 10),
          if (_selectedSemester != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_periods.length} periods · ${_periods.where((p) => p.isActive).length} active',
                style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildGrid() {
    // Group periods by day
    final byDay = <String, List<TeachingPeriod>>{};
    for (final day in _days) {
      byDay[day] = _periods.where((p) => p.dayOfWeek == day).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _days.length,
      itemBuilder: (_, i) {
        final day = _days[i];
        final dayPeriods = byDay[day] ?? [];
        if (dayPeriods.isEmpty) return const SizedBox.shrink();
        final color = _dayColors[day] ?? AppColors.primary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(day, style: AppTypography.titleMedium.copyWith(color: color)),
              const SizedBox(width: 8),
              Text('(${dayPeriods.length})', style: AppTypography.bodySmall),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dayPeriods.map((p) => _buildChip(p, color)).toList(),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildChip(TeachingPeriod p, Color color) {
    return GestureDetector(
      onTap: () => _showForm(context, period: p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: p.isActive ? color.withAlpha(20) : AppColors.divider,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.isActive ? color.withAlpha(80) : AppColors.textSecondary.withAlpha(60)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.schedule, size: 14, color: p.isActive ? color : AppColors.textSecondary),
          const SizedBox(width: 4),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${p.startHHMM}–${p.endHHMM}',
                style: AppTypography.labelLarge.copyWith(
                    color: p.isActive ? color : AppColors.textSecondary, fontSize: 12)),
            Text('${p.durationMinutes}min',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ]),
          if (!p.isActive) ...[
            const SizedBox(width: 4),
            Icon(Icons.block, size: 12, color: AppColors.textSecondary),
          ],
        ]),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.schedule, size: 56, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text('No teaching periods defined', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Text('Use + to add periods, or Bulk Add to create a standard weekly schedule.', style: AppTypography.bodySmall, textAlign: TextAlign.center),
    ]),
  );

  // ── Form ─────────────────────────────────────────────────────────────────────

  void _showForm(BuildContext context, {TeachingPeriod? period}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PeriodForm(
        period: period,
        semesters: _semesters,
        selectedSemesterId: _selectedSemester?.id,
        onSaved: (p) async {
          Navigator.pop(ctx);
          try {
            period == null ? await _service.createTeachingPeriod(p) : await _service.updateTeachingPeriod(p);
            _loadPeriods();
          } catch (e) { _showError(e); }
        },
        onDelete: period == null ? null : (p) async {
          Navigator.pop(ctx);
          try { await _service.deleteTeachingPeriod(p.id); _loadPeriods(); } catch (e) { _showError(e); }
        },
      ),
    );
  }

  // ── Bulk Add ──────────────────────────────────────────────────────────────────

  void _showBulkAdd(BuildContext context) {
    if (_selectedSemester == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a semester first.')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Add Standard Periods'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This will create the following periods for ${_selectedSemester!.name}:',
              style: AppTypography.bodySmall),
          const SizedBox(height: 8),
          Text('Mon–Fri: 08:00–10:00, 10:00–12:00, 13:00–15:00, 15:00–17:00',
              style: AppTypography.bodyMedium),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _createStandardPeriods();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createStandardPeriods() async {
    if (_selectedSemester == null) return;
    final days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'];
    final slots = [('08:00:00', '10:00:00'), ('10:00:00', '12:00:00'), ('13:00:00', '15:00:00'), ('15:00:00', '17:00:00')];
    int created = 0;
    for (final day in days) {
      for (final slot in slots) {
        try {
          final p = TeachingPeriod(id: 0, semesterId: _selectedSemester!.id, semesterName: _selectedSemester!.name, academicYearName: '', dayOfWeek: day, dayDisplay: day, startTime: slot.$1, endTime: slot.$2, label: '', isActive: true, durationMinutes: 120);
          await _service.createTeachingPeriod(p);
          created++;
        } catch (_) {} // skip if already exists
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created $created new periods.'), backgroundColor: AppColors.statusFree));
      _loadPeriods();
    }
  }

  void _showError(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
  }

  Widget _dd<T>(String label, T value, List<T> items, String Function(T) display, ValueChanged<T> onChanged) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: DropdownButtonFormField<T>(
        value: value,
        isDense: true,
        decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(display(i), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

// ── Period form ───────────────────────────────────────────────────────────────

class _PeriodForm extends StatefulWidget {
  final TeachingPeriod? period;
  final List<Semester> semesters;
  final int? selectedSemesterId;
  final Future<void> Function(TeachingPeriod) onSaved;
  final Future<void> Function(TeachingPeriod)? onDelete;

  const _PeriodForm({this.period, required this.semesters, this.selectedSemesterId, required this.onSaved, this.onDelete});
  @override
  State<_PeriodForm> createState() => _PeriodFormState();
}

class _PeriodFormState extends State<_PeriodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  int? _semId;
  String _day = 'MONDAY';
  String _start = '08:00:00', _end = '10:00:00';
  bool _isActive = true, _saving = false;

  static const _days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
  static const _times = ['07:00:00','08:00:00','09:00:00','10:00:00','11:00:00','12:00:00','13:00:00','14:00:00','15:00:00','16:00:00','17:00:00','18:00:00'];

  String _hm(String t) { final p = t.split(':'); return '${p[0]}:${p[1]}'; }

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.period?.label ?? '');
    _semId = widget.period?.semesterId ?? widget.selectedSemesterId ?? (widget.semesters.isNotEmpty ? widget.semesters.first.id : null);
    _day = widget.period?.dayOfWeek ?? 'MONDAY';
    _start = widget.period?.startTime ?? '08:00:00';
    _end = widget.period?.endTime ?? '10:00:00';
    _isActive = widget.period?.isActive ?? true;
  }

  @override
  void dispose() { _label.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(widget.period == null ? 'New Teaching Period' : 'Edit Period', style: AppTypography.headlineMedium),
          if (widget.onDelete != null)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.error), onPressed: () => widget.onDelete!(widget.period!)),
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _semId,
          decoration: const InputDecoration(labelText: 'Semester'),
          items: widget.semesters.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.academicYearName} — ${s.name}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _semId = v),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _day,
          decoration: const InputDecoration(labelText: 'Day'),
          items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (v) => setState(() => _day = v!),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: _start, decoration: const InputDecoration(labelText: 'Start'), items: _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(), onChanged: (v) => setState(() => _start = v!))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(value: _end, decoration: const InputDecoration(labelText: 'End'), items: _times.map((t) => DropdownMenuItem(value: t, child: Text(_hm(t)))).toList(), onChanged: (v) => setState(() => _end = v!))),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: _label, decoration: const InputDecoration(labelText: 'Label (optional)', hintText: 'e.g. Period 1')),
        const SizedBox(height: 12),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), subtitle: const Text('Inactive periods are excluded from generation'), value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : () async {
            if (!_formKey.currentState!.validate() || _semId == null) return;
            setState(() => _saving = true);
            await widget.onSaved(TeachingPeriod(id: widget.period?.id ?? 0, semesterId: _semId!, semesterName: '', academicYearName: '', dayOfWeek: _day, dayDisplay: _day, startTime: _start, endTime: _end, label: _label.text.trim(), isActive: _isActive, durationMinutes: 0));
          },
          child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2)) : Text(widget.period == null ? 'Create' : 'Save'),
        )),
      ])),
    );
  }
}
