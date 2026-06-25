import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../../../features/academics/models/academic_models.dart';
import '../../../features/academics/services/academics_service.dart';
import '../models/timetable_lifecycle.dart';
import '../services/timetable_service.dart';

class ConflictResolutionScreen extends StatefulWidget {
  const ConflictResolutionScreen({super.key});
  @override
  State<ConflictResolutionScreen> createState() => _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen>
    with SingleTickerProviderStateMixin {
  final _ttService = TimetableService();
  final _acService = AcademicsService();

  List<Semester> _semesters = [];
  Semester? _selectedSemester;
  List<ConflictItem> _conflicts = [];
  bool _loading = false;
  bool _refLoaded = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRef();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRef() async {
    try {
      final sems = await _acService.getSemesters();
      if (mounted) {
        setState(() {
          _semesters = sems;
          _selectedSemester = sems.isNotEmpty ? sems.first : null;
          _refLoaded = true;
        });
        await _loadConflicts();
      }
    } catch (_) {}
  }

  Future<void> _loadConflicts() async {
    if (_selectedSemester == null) return;
    setState(() => _loading = true);
    try {
      final all = await _ttService.getConflicts(semesterId: _selectedSemester!.id);
      if (mounted) setState(() => _conflicts = all);
    } catch (_) {
      // _conflicts stays empty — user sees "No conflicts" state
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ConflictItem> get _openConflicts => _conflicts.where((c) => c.isOpen).toList();
  List<ConflictItem> get _resolvedConflicts => _conflicts.where((c) => !c.isOpen).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Conflict Resolution',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
            onPressed: _loadConflicts,
          ),
        ],
      ),
      body: Column(children: [
        _buildSemesterBar(),
        if (_refLoaded) TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Open (${_openConflicts.length})'),
            Tab(text: 'Resolved (${_resolvedConflicts.length})'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : !_refLoaded
                  ? const SizedBox.shrink()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildConflictList(_openConflicts, open: true),
                        _buildConflictList(_resolvedConflicts, open: false),
                      ],
                    ),
        ),
      ]),
    );
  }

  Widget _buildSemesterBar() => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: DropdownButtonFormField<Semester>(
      value: _selectedSemester,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Semester', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      items: _semesters.map((s) => DropdownMenuItem(value: s, child: Text('${s.academicYearName} — ${s.name}', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (s) { setState(() { _selectedSemester = s; _conflicts = []; }); _loadConflicts(); },
    ),
  );

  Widget _buildConflictList(List<ConflictItem> items, {required bool open}) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(open ? Icons.check_circle_outline : Icons.history, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(open ? 'No open conflicts' : 'No resolved conflicts', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
          if (open) ...[
            const SizedBox(height: 4),
            Text('All conflicts are resolved. You can publish the timetable.', style: AppTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadConflicts,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildConflictCard(items[i], open: open),
      ),
    );
  }

  Widget _buildConflictCard(ConflictItem c, {required bool open}) {
    final (icon, color) = switch (c.conflictType) {
      'VENUE_CONFLICT' => (Icons.location_city_outlined, AppColors.statusInUse),
      'LECTURER_CONFLICT' => (Icons.person_outlined, AppColors.statusExpired),
      _ => (Icons.group_outlined, AppColors.statusBooked),
    };

    return ReusableCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(c.typeDisplay, style: AppTypography.titleMedium.copyWith(color: color))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: open ? AppColors.statusExpired.withAlpha(15) : AppColors.statusFree.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(c.status, style: AppTypography.caption.copyWith(
              color: open ? AppColors.statusExpired : AppColors.statusFree,
              fontWeight: FontWeight.w700,
            )),
          ),
        ]),
        const SizedBox(height: 8),
        Text(c.message, style: AppTypography.bodySmall),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _entryRow('Entry A', c.entryA, color),
        const SizedBox(height: 4),
        _entryRow('Entry B', c.entryB, color),

        // Resolution info (resolved conflicts)
        if (!open && c.resolutionNote != null && c.resolutionNote!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.statusFree.withAlpha(10), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resolution', style: AppTypography.labelLarge.copyWith(color: AppColors.statusFree)),
              Text(c.resolutionNote!, style: AppTypography.bodySmall),
              if (c.resolvedBy != null) Text('by ${c.resolvedBy}', style: AppTypography.caption),
            ]),
          ),
        ],

        // Resolve button for open conflicts
        if (open) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Mark as Resolved'),
              style: TextButton.styleFrom(foregroundColor: AppColors.statusFree),
              onPressed: () => _showResolveDialog(c),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _entryRow(String label, ConflictEntry e, Color color) => Row(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
    ),
    const SizedBox(width: 8),
    Text('${e.course}  •  ${e.day}  ${e.time}', style: AppTypography.bodySmall),
  ]);

  void _showResolveDialog(ConflictItem conflict) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Conflict'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(conflict.message, style: AppTypography.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Resolution Note *',
              hintText: 'Describe how this conflict was resolved...',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _resolve(conflict, ctrl.text.trim());
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(ConflictItem conflict, String note) async {
    try {
      final result = await _ttService.resolveConflict(conflict.id, note);
      if (mounted) {
        _showSnack(result['message'] ?? 'Resolved.', success: result['success'] == true);
        await _loadConflicts();
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', success: false);
    }
  }

  void _showSnack(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.statusFree : AppColors.error,
    ));
  }
}
