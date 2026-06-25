import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/venue_models.dart';
import '../services/venues_service.dart';

class VenueListScreen extends StatefulWidget {
  const VenueListScreen({super.key});
  @override
  State<VenueListScreen> createState() => _VenueListScreenState();
}

class _VenueListScreenState extends State<VenueListScreen> {
  final _service = VenuesService();

  List<Venue> _venues = [];
  List<Building> _buildings = [];
  bool _loading = false;

  // Filters
  final _searchCtrl = TextEditingController();
  int? _selectedBuildingId;
  String? _selectedType;
  String? _selectedStatus;
  bool _accessibleOnly = false;
  final _minCapCtrl = TextEditingController();
  final _maxCapCtrl = TextEditingController();

  static const _types = [
    ('LECTURE_HALL', 'Lecture Hall'),
    ('CLASSROOM', 'Classroom'),
    ('LABORATORY', 'Laboratory'),
    ('COMPUTER_LAB', 'Computer Lab'),
    ('SEMINAR_ROOM', 'Seminar Room'),
    ('AUDITORIUM', 'Auditorium'),
  ];
  static const _statuses = ['FREE', 'BOOKED', 'IN_USE', 'EXPIRED', 'MAINTENANCE'];

  @override
  void initState() {
    super.initState();
    _loadBuildings();
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _minCapCtrl.dispose();
    _maxCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBuildings() async {
    try {
      final b = await _service.getBuildings();
      if (mounted) setState(() => _buildings = b);
    } catch (_) {}
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final venues = await _service.searchVenues(
        buildingId: _selectedBuildingId,
        venueType: _selectedType,
        status: _selectedStatus,
        minCapacity: int.tryParse(_minCapCtrl.text),
        maxCapacity: int.tryParse(_maxCapCtrl.text),
        accessible: _accessibleOnly ? true : null,
        search: _searchCtrl.text,
        activeOnly: true,
      );
      if (mounted) setState(() => _venues = venues);
    } catch (_) {
      if (mounted) setState(() => _venues = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _minCapCtrl.clear();
    _maxCapCtrl.clear();
    setState(() {
      _selectedBuildingId = null;
      _selectedType = null;
      _selectedStatus = null;
      _accessibleOnly = false;
    });
    _search();
  }

  Color _statusColor(String s) => switch (s) {
        'FREE'        => AppColors.statusFree,
        'BOOKED'      => AppColors.statusBooked,
        'IN_USE'      => AppColors.statusInUse,
        'EXPIRED'     => AppColors.statusExpired,
        _             => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Find a Venue',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.map_outlined, color: AppColors.textOnPrimary),
            tooltip: 'Switch to Map',
            onPressed: () => context.push('/venues/map'),
          ),
        ],
      ),
      body: Column(children: [
        _buildFilterPanel(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(children: [
        // Search bar
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search code or name…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); _search(); })
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            filled: true,
            fillColor: AppColors.background,
          ),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 8),
        // Filter row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            // Building filter
            _filterDropdown<int?>(
              'Building',
              _selectedBuildingId,
              [const DropdownMenuItem(value: null, child: Text('All Buildings')),
               ..._buildings.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis)))],
              (v) { setState(() => _selectedBuildingId = v); _search(); },
              120,
            ),
            const SizedBox(width: 8),
            // Type filter
            _filterDropdown<String?>(
              'Type',
              _selectedType,
              [const DropdownMenuItem(value: null, child: Text('All Types')),
               ..._types.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)))],
              (v) { setState(() => _selectedType = v); _search(); },
              130,
            ),
            const SizedBox(width: 8),
            // Status filter
            _filterDropdown<String?>(
              'Status',
              _selectedStatus,
              [const DropdownMenuItem(value: null, child: Text('Any Status')),
               ..._statuses.map((s) => DropdownMenuItem(value: s, child: Text(s)))],
              (v) { setState(() => _selectedStatus = v); _search(); },
              110,
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          // Capacity range
          SizedBox(
            width: 80,
            child: TextField(
              controller: _minCapCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min cap', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onSubmitted: (_) => _search(),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _maxCapCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max cap', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          // Accessible toggle
          FilterChip(
            label: const Text('Accessible', style: TextStyle(fontSize: 12)),
            selected: _accessibleOnly,
            onSelected: (v) { setState(() => _accessibleOnly = v); _search(); },
            selectedColor: AppColors.statusFree.withAlpha(25),
            checkmarkColor: AppColors.statusFree,
            side: BorderSide(color: _accessibleOnly ? AppColors.statusFree : AppColors.divider),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Clear'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, visualDensity: VisualDensity.compact),
          ),
          IconButton(
            onPressed: _search,
            icon: const Icon(Icons.search),
            color: AppColors.primary,
            iconSize: 20,
            tooltip: 'Search',
          ),
        ]),
      ]),
    );
  }

  Widget _filterDropdown<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged, double width) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_venues.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text('No venues found', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text('Try adjusting your filters.', style: AppTypography.bodySmall),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _venues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _VenueCard(
        venue: _venues[i],
        statusColor: _statusColor(_venues[i].status),
        onTap: () => context.push('/venues/detail/${_venues[i].id}'),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final Color statusColor;
  final VoidCallback onTap;
  const _VenueCard({required this.venue, required this.statusColor, required this.onTap});

  IconData get _typeIcon => switch (venue.venueType) {
        'LECTURE_HALL'  => Icons.school_outlined,
        'CLASSROOM'     => Icons.meeting_room_outlined,
        'LABORATORY'    => Icons.science_outlined,
        'COMPUTER_LAB'  => Icons.computer_outlined,
        'SEMINAR_ROOM'  => Icons.groups_outlined,
        _               => Icons.room_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return ReusableCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_typeIcon, color: statusColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(venue.code, style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
          Text(venue.name, style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(venue.buildingName, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(venue.status,
                style: AppTypography.caption.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.people_outline, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text('${venue.capacity}', style: AppTypography.caption),
          ]),
          if (venue.accessibility.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.accessible_outlined, size: 14, color: AppColors.statusFree),
            ),
        ]),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
      ]),
    );
  }
}
