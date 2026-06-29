import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../models/venue_map_data.dart';
import '../services/venues_service.dart';

class VenueMapScreen extends StatefulWidget {
  const VenueMapScreen({super.key});
  @override
  State<VenueMapScreen> createState() => _VenueMapScreenState();
}

class _VenueMapScreenState extends State<VenueMapScreen> {
  final _service = VenuesService();
  final _mapController = MapController();

  List<VenueMapData> _allVenues = [];
  List<VenueMapData> _filtered = [];
  VenueMapData? _selected;
  bool _loading = true;
  String _statusFilter = 'ALL';
  final _searchCtrl = TextEditingController();

  // Campus center (Block A area, Tanzania)
  static const _center = LatLng(-6.7718, 39.2738);

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final venues = await _service.getMapData();
      if (mounted) setState(() { _allVenues = venues; _filter(); });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allVenues.where((v) {
        final matchStatus = _statusFilter == 'ALL' || v.status == _statusFilter;
        final matchSearch = q.isEmpty ||
            v.code.toLowerCase().contains(q) ||
            v.name.toLowerCase().contains(q) ||
            v.buildingName.toLowerCase().contains(q);
        return matchStatus && matchSearch;
      }).toList();
      _selected = null;
    });
  }

  void _applySearch() => _filter();

  void _setStatusFilter(String f) {
    _statusFilter = f;
    _filter();
  }

  Color _colorFor(String s) => switch (s) {
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
        title: 'Venue Map',
        showBackButton: true,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textOnPrimary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(child: _buildMap()),
                _buildFilterRow(),
                if (_selected != null) _buildSelectedCard(),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search venue code or name…',
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () { _searchCtrl.clear(); },
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final center = _filtered.isNotEmpty
        ? LatLng(_filtered.first.lat, _filtered.first.lng)
        : _center;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 18.0,
        maxZoom: 20.0,
        minZoom: 10.0,
        onTap: (_, __) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ac.tz.utlva.mobile',
          maxZoom: 20,
        ),
        MarkerLayer(
          markers: _filtered.map((v) {
            final color = _colorFor(v.status);
            return Marker(
              point: LatLng(v.lat, v.lng),
              width: 48,
              height: 48,
              child: GestureDetector(
                onTap: () {
                  setState(() => _selected = v);
                  _mapController.move(LatLng(v.lat, v.lng), 19.0);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _selected?.id == v.id ? 52 : 44,
                  height: _selected?.id == v.id ? 52 : 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selected?.id == v.id ? Colors.white : Colors.white70,
                      width: _selected?.id == v.id ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withAlpha(120),
                        blurRadius: _selected?.id == v.id ? 10 : 4,
                        spreadRadius: _selected?.id == v.id ? 2 : 0,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    v.code.contains('-') ? v.code.split('-').first : v.code.substring(0, 2),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    const filters = ['ALL', 'FREE', 'IN_USE', 'BOOKED', 'EXPIRED'];
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
            Text('${_filtered.length} venues', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ...filters.map((f) {
              final selected = _statusFilter == f;
              final color = f == 'ALL' ? AppColors.primary : _colorFor(f);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(f, style: AppTypography.labelMedium.copyWith(
                    color: selected ? color : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  )),
                  selected: selected,
                  onSelected: (_) => _setStatusFilter(f),
                  selectedColor: color.withAlpha(25),
                  checkmarkColor: color,
                  side: BorderSide(color: selected ? color : AppColors.divider),
                  backgroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
          ],
        ),
    );
  }

  Widget _buildSelectedCard() {
    final v = _selected!;
    final color = _colorFor(v.status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_venueIcon(v.venueType), color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v.code, style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
          Text(v.name, style: AppTypography.bodySmall),
          Row(children: [
            Icon(Icons.people_outline, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text('${v.capacity}', style: AppTypography.caption),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(v.statusDisplay,
                  style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
        ])),
        TextButton(
          onPressed: () => context.push('/venues/detail/${v.id}', extra: v),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: const Row(children: [
            Text('Details'),
            SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 16),
          ],
          ),
        ),
      ]),
    );
  }

  IconData _venueIcon(String type) => switch (type) {
        'LECTURE_HALL'  => Icons.school_outlined,
        'CLASSROOM'     => Icons.meeting_room_outlined,
        'LABORATORY'    => Icons.science_outlined,
        'COMPUTER_LAB'  => Icons.computer_outlined,
        'SEMINAR_ROOM'  => Icons.groups_outlined,
        'AUDITORIUM'    => Icons.theater_comedy_outlined,
        _               => Icons.room_outlined,
      };
}
