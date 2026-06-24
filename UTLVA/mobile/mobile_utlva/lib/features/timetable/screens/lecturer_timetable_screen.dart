import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/timetable_grid_view.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';

class LecturerTimetableScreen extends StatefulWidget {
  const LecturerTimetableScreen({super.key});
  @override
  State<LecturerTimetableScreen> createState() => _LecturerTimetableScreenState();
}

class _LecturerTimetableScreenState extends State<LecturerTimetableScreen> {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  List<TimetableEntry> _entries = [];
  List<AcademicYear> _years = [];
  List<Semester> _semesters = [];
  AcademicYear? _selectedYear;
  Semester? _selectedSemester;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final refs = await Future.wait([_acService.getYears(), _acService.getSemesters()]);
      _years = refs[0] as List<AcademicYear>;
      _semesters = refs[1] as List<Semester>;
      if (_years.isNotEmpty) _selectedYear = _years.first;
      if (_semesters.isNotEmpty) _selectedSemester = _semesters.first;
      await _loadEntries();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      _entries = await _ttService.getLecturerTimetable(
        academicYearId: _selectedYear?.id,
        semesterId: _selectedSemester?.id,
      );
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'My Timetable'),
      body: Column(
        children: [
          // Filter bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(_selectedYear?.name ?? 'All Years', Icons.calendar_today_outlined, AppColors.primary,
                    () => _showPicker<AcademicYear>('Academic Year', _years, _selectedYear, (y) { setState(() => _selectedYear = y); _loadEntries(); }, (y) => y.name)),
                const SizedBox(width: 8),
                _chip(_selectedSemester?.name ?? 'All Semesters', Icons.date_range_outlined, AppColors.accent,
                    () => _showPicker<Semester>('Semester', _semesters, _selectedSemester, (s) { setState(() => _selectedSemester = s); _loadEntries(); }, (s) => s.name)),
                const SizedBox(width: 8),
                TextButton.icon(icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh'), onPressed: _loadEntries),
              ]),
            ),
          ),
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
                            _buildSummary(),
                            const SizedBox(height: 14),
                            TimetableGridView(entries: _entries),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
      onPressed: onTap,
      backgroundColor: color.withAlpha(15),
      side: BorderSide(color: color.withAlpha(60)),
    );
  }

  Widget _buildSummary() {
    final days = _entries.map((e) => e.dayOfWeek).toSet().length;
    return Row(children: [
      const Icon(Icons.schedule, size: 16, color: AppColors.primary),
      const SizedBox(width: 6),
      Text('${_entries.length} sessions across $days days', style: AppTypography.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.event_busy, size: 56, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text('No sessions assigned yet', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Text('Contact the Timetable Coordinator.', style: AppTypography.bodySmall),
    ]),
  );

  void _showPicker<T>(String title, List<T> items, T? selected, ValueChanged<T> onSelect, String Function(T) label) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.headlineMedium),
          const SizedBox(height: 16),
          ...items.map((item) => ListTile(
            title: Text(label(item)),
            trailing: item == selected ? const Icon(Icons.check, color: AppColors.primary) : null,
            onTap: () { Navigator.pop(ctx); onSelect(item); },
          )),
        ]),
      ),
    );
  }
}
