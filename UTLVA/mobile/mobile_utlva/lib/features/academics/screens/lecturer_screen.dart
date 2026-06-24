import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/academic_models.dart';
import '../services/academics_service.dart';

class LecturerScreen extends StatefulWidget {
  const LecturerScreen({super.key});
  @override
  State<LecturerScreen> createState() => _LecturerScreenState();
}

class _LecturerScreenState extends State<LecturerScreen> {
  final _service = AcademicsService();
  List<Lecturer> _items = [];
  List<Course> _courses = [];
  List<AcademicYear> _years = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_service.getLecturers(), _service.getCourses(), _service.getYears()]);
      _items = r[0] as List<Lecturer>;
      _courses = r[1] as List<Course>;
      _years = r[2] as List<AcademicYear>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Lecturers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No lecturer profiles yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildTile(_items[i]))),
    );
  }

  Widget _buildTile(Lecturer l) {
    final assignedCount = l.courseAssignments.length;
    return ReusableCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: AppColors.primary, radius: 22, child: Text(l.fullName.isNotEmpty ? l.fullName[0].toUpperCase() : 'L', style: const TextStyle(color: AppColors.textOnPrimary, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.fullName, style: AppTypography.titleMedium),
            Text(l.email, style: AppTypography.bodySmall),
            if (l.departmentName != null) Text(l.departmentName!, style: AppTypography.bodySmall.copyWith(color: AppColors.accent)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.primary.withAlpha(20), borderRadius: BorderRadius.circular(12)),
            child: Text('${l.staffNumber}', style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (assignedCount > 0) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text('Assigned Courses ($assignedCount)', style: AppTypography.labelMedium),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: l.courseAssignments.map((a) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.accent.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: Text(a['course_code'] ?? '', style: AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
            );
          }).toList()),
        ],
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(icon: const Icon(Icons.book_outlined, size: 16), label: const Text('Assign Course'), onPressed: () => _showAssignCourse(l)),
        ]),
      ]),
    );
  }

  void _showAssignCourse(Lecturer l) {
    int? courseId;
    int? yearId;
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign Course to ${l.fullName}', style: AppTypography.headlineMedium),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(decoration: const InputDecoration(labelText: 'Course'), items: _courses.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.courseCode} — ${c.courseName}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => ss(() => courseId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(value: yearId, decoration: const InputDecoration(labelText: 'Academic Year (optional)'), items: [const DropdownMenuItem(value: null, child: Text('None')), ..._years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.name)))], onChanged: (v) => ss(() => yearId = v)),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: courseId == null ? null : () async {
              Navigator.pop(ctx);
              try { await _service.assignCourse(l.id, courseId!, academicYearId: yearId); _load(); }
              catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); }
            },
            child: const Text('Assign'),
          )),
        ]),
      )));
  }
}
