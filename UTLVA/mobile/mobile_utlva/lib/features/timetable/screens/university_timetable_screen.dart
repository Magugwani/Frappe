import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';

import '../../../core/widgets/timetable_grid_view.dart';
import '../../academics/models/academic_models.dart';
import '../../academics/services/academics_service.dart';
import '../../venues/models/venue_map_data.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';

/// Which mode this timetable screen runs in.
enum TimetableViewMode {
  /// Static official timetable — read-only, no venue status, no navigation.
  /// Published once per semester. Students and lecturers see this as the
  /// authoritative schedule.
  official,

  /// Live dynamic timetable — shows real-time venue status (FREE/BOOKED/IN_USE)
  /// as a coloured dot in every session card, plus a navigation icon that opens
  /// Google Maps to the venue. Refreshes on pull-down.
  live,
}

class UniversityTimetableScreen extends StatefulWidget {
  final TimetableViewMode mode;

  const UniversityTimetableScreen({super.key, required this.mode});

  @override
  State<UniversityTimetableScreen> createState() => _UniversityTimetableScreenState();
}

class _UniversityTimetableScreenState extends State<UniversityTimetableScreen> {
  final _ttService  = TimetableService();
  final _acService  = AcademicsService();

  List<TimetableEntry> _entries = [];
  List<AcademicYear>   _years = [];
  List<Semester>       _semesters = [];
  List<Programme>      _programmes = [];

  AcademicYear? _selectedYear;
  Semester?     _selectedSemester;
  Programme?    _selectedProgramme;

  bool _loading   = false;
  bool _refLoaded = false;
  int  _loadSeq   = 0;

  @override
  void initState() {
    super.initState();
    _loadRef();
  }

  Future<void> _loadRef() async {
    try {
      final r = await Future.wait([
        _acService.getYears(),
        _acService.getSemesters(),
        _acService.getProgrammes(),
      ]);
      if (!mounted) return;
      setState(() {
        _years      = r[0] as List<AcademicYear>;
        _semesters  = r[1] as List<Semester>;
        _programmes = r[2] as List<Programme>;
        _selectedYear = _years.firstWhere((y) => y.isActive,
            orElse: () => _years.isNotEmpty ? _years.first : _years.first);
        _selectedSemester = _semesters.firstWhere(
          (s) => _selectedYear != null && s.academicYearId == _selectedYear!.id,
          orElse: () => _semesters.isNotEmpty ? _semesters.first : _semesters.first,
        );
        _refLoaded = true;
      });
      await _loadEntries();
    } catch (_) {}
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    try {
      // Build URL manually — existing getEntries already supports these params
      final entries = await _ttService.getEntries(
        academicYearId: _selectedYear?.id,
        semesterId: _selectedSemester?.id,
        programmeId: _selectedProgramme?.id,
        status: 'PUBLISHED',
      );
      if (mounted && seq == _loadSeq) setState(() => _entries = entries);
    } catch (_) {
      if (mounted && seq == _loadSeq) setState(() => _entries = []);
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  // ── Venue navigation ────────────────────────────────────────────────────────

  Future<void> _navigateToVenue(TimetableEntry entry) async {
    if (!entry.hasVenueCoordinates) return;
    final lat = entry.venueLatitude!;
    final lng = entry.venueLongitude!;

    // Try to open in app first (VenueDetailScreen)
    if (entry.venueId != null) {
      context.push(
        '/venues/detail/${entry.venueId}',
        extra: VenueMapData(
          id: entry.venueId!,
          code: entry.venueCode ?? '',
          name: entry.venueName ?? '',
          buildingName: entry.venueBuildingName ?? '',
          floor: entry.venueFloor ?? 0,
          capacity: 0,
          venueType: '',
          venueTypeDisplay: '',
          resources: [],
          accessibility: [],
          status: entry.venueStatus ?? 'FREE',
          statusDisplay: entry.venueStatusDisplay ?? '',
          lat: lat,
          lng: lng,
        ),
      );
      return;
    }

    // Fallback: open Google Maps
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Legend for live mode ────────────────────────────────────────────────────

  static const _liveLegend = [
    TimetableLegendItem(color: AppColors.statusFree,    label: 'FREE'),
    TimetableLegendItem(color: AppColors.statusBooked,  label: 'BOOKED'),
    TimetableLegendItem(color: AppColors.statusInUse,   label: 'IN USE'),
    TimetableLegendItem(color: AppColors.statusExpired, label: 'EXPIRED'),
  ];

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLive = widget.mode == TimetableViewMode.live;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: isLive ? 'Live Timetable' : 'Official Timetable',
        showBackButton: true,
        extraActions: [
          if (isLive)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
              tooltip: 'Refresh venue status',
              onPressed: _loadEntries,
            ),
          // Toggle between modes
          IconButton(
            icon: Icon(
              isLive ? Icons.grid_on_outlined : Icons.sensors_outlined,
              color: AppColors.textOnPrimary,
            ),
            tooltip: isLive ? 'Switch to Official View' : 'Switch to Live View',
            onPressed: () => context.pushReplacement(
              isLive ? '/timetable/official' : '/timetable/live',
            ),
          ),
        ],
      ),
      body: Column(children: [
        _buildFilterBar(),
        if (isLive) _buildLiveStatusBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody(isLive)),
      ]),
    );
  }

  Widget _buildFilterBar() {
    // Wrap is used instead of SingleChildScrollView + Row because
    // SingleChildScrollView(horizontal) absorbs pointer events on web/desktop,
    // causing ActionChips to become unresponsive.
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _filterChip<AcademicYear>(
            label: _selectedYear?.name ?? 'Year',
            color: AppColors.statusBooked,
            onTap: () => _showPicker<AcademicYear>(
              'Academic Year', _years, _selectedYear,
              (y) { setState(() => _selectedYear = y); _loadEntries(); },
              (y) => y.name,
            ),
          ),
          _filterChip<Semester>(
            label: _selectedSemester?.name ?? 'Semester',
            color: AppColors.statusBooked,
            onTap: () => _showPicker<Semester>(
              'Semester',
              _semesters.where((s) =>
                  _selectedYear == null || s.academicYearId == _selectedYear!.id).toList(),
              _selectedSemester,
              (s) { setState(() => _selectedSemester = s); _loadEntries(); },
              (s) => s.name,
            ),
          ),
          _filterChip<Programme?>(
            label: _selectedProgramme?.code ?? 'All Programmes',
            color: _selectedProgramme != null ? AppColors.statusBooked : AppColors.textSecondary,
            onTap: () => _showPickerWithNull(
              'Programme',
              _programmes,
              _selectedProgramme,
              (p) { setState(() => _selectedProgramme = p); _loadEntries(); },
              (p) => p.code,
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Load'),
            onPressed: _loadEntries,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusBar() {
    // Show legend + entry count
    final statusCounts = <String, int>{};
    for (final e in _entries) {
      if (e.venueStatus != null) {
        statusCounts[e.venueStatus!] = (statusCounts[e.venueStatus!] ?? 0) + 1;
      }
    }
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Live venue status', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ..._liveLegend.map((item) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: item.color, shape: BoxShape.circle)),
            const SizedBox(width: 3),
            Text(
              '${item.label}${statusCounts.containsKey(item.label) ? ' (${statusCounts[item.label]})' : ''}',
              style: AppTypography.caption.copyWith(fontSize: 10),
            ),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('tap  to navigate', style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontSize: 10)),
            const Icon(Icons.navigation_outlined, size: 10, color: AppColors.textSecondary),
          ]),
        ],
      ),
    );
  }

  Widget _buildBody(bool isLive) {
    if (!_refLoaded || _loading) {
      // AppColors.primary is sky blue — invisible against the light blue background.
      // Use statusBooked (dark blue) so the spinner is clearly visible.
      return const Center(child: CircularProgressIndicator(color: AppColors.statusBooked));
    }
    if (_entries.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_outlined, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            'No published timetable found',
            style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedProgramme != null
                ? 'No published entries for ${_selectedProgramme!.code} in the selected semester.'
                : 'Select a semester and programme, then tap Load.',
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _buildSummaryChips(),
          const SizedBox(height: 12),
          TimetableGridView(
            entries: _entries,
            showOnlyDaysWithEntries: false,
            showVenueStatus: isLive,
            onVenueNavigate: isLive ? _navigateToVenue : null,
            legends: isLive ? _liveLegend : null,
            entryColorBuilder: isLive
                ? (e) {
                    // In live mode, card color reflects venue status
                    return switch (e.venueStatus) {
                      'IN_USE'      => AppColors.statusInUse.withAlpha(200),
                      'BOOKED'      => AppColors.statusBooked.withAlpha(200),
                      'EXPIRED'     => AppColors.statusExpired.withAlpha(200),
                      'MAINTENANCE' => AppColors.textSecondary,
                      _             => AppColors.primary, // FREE or unknown
                    };
                  }
                : null,
          ),
        ]),
      ),
    );
  }

  Widget _buildSummaryChips() {
    final published = _entries.where((e) => e.status == 'PUBLISHED').length;
    final days = _entries.map((e) => e.dayOfWeek).toSet().length;
    return Wrap(spacing: 8, runSpacing: 4, children: [
      _chip('$published sessions', Icons.event_outlined, AppColors.primary),
      _chip('$days day${days == 1 ? '' : 's'}', Icons.calendar_today_outlined, AppColors.accent),
      if (_selectedProgramme != null)
        _chip(_selectedProgramme!.code, Icons.school_outlined, AppColors.statusBooked),
      if (_selectedSemester != null)
        _chip(_selectedSemester!.name, Icons.date_range_outlined, AppColors.textSecondary),
    ]);
  }

  Widget _chip(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withAlpha(50)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _filterChip<T>({required String label, required Color color, required VoidCallback onTap}) {
    return ActionChip(
      avatar: Icon(Icons.arrow_drop_down, size: 16, color: color),
      label: Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
      onPressed: onTap,
      backgroundColor: color.withAlpha(12),
      side: BorderSide(color: color.withAlpha(60)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────

  void _showPicker<T>(String title, List<T> items, T? selected,
      ValueChanged<T> onSelect, String Function(T) label) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.headlineMedium),
          const SizedBox(height: 12),
          ...items.map((item) => ListTile(
            title: Text(label(item)),
            trailing: item == selected ? const Icon(Icons.check, color: AppColors.primary) : null,
            onTap: () { Navigator.pop(ctx); onSelect(item); },
          )),
        ]),
      ),
    );
  }

  void _showPickerWithNull(String title, List<Programme> items, Programme? selected,
      ValueChanged<Programme?> onSelect, String Function(Programme) label) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.headlineMedium),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('All Programmes'),
            trailing: selected == null ? const Icon(Icons.check, color: AppColors.primary) : null,
            onTap: () { Navigator.pop(ctx); onSelect(null); },
          ),
          ...items.map((item) => ListTile(
            title: Text(label(item)),
            subtitle: Text(item.name, style: AppTypography.bodySmall),
            trailing: item == selected ? const Icon(Icons.check, color: AppColors.primary) : null,
            onTap: () { Navigator.pop(ctx); onSelect(item); },
          )),
        ]),
      ),
    );
  }
}
