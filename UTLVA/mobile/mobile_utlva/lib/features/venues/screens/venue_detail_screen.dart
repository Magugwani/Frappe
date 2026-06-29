import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/reusable_card.dart';
import '../models/venue_map_data.dart';
import '../models/venue_models.dart';
import '../services/venues_service.dart';

class VenueDetailScreen extends StatefulWidget {
  final int venueId;
  final VenueMapData? prefetched;

  const VenueDetailScreen({super.key, required this.venueId, this.prefetched});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  final _service = VenuesService();
  VenueMapData? _venue;
  List<VenueStatusHistory> _history = [];
  bool _loading = true;
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _venue = widget.prefetched;
    if (_venue != null) _loading = false;
    _loadHistory();
    if (_venue == null) _loadVenueFromApi();
  }

  Future<void> _loadVenueFromApi() async {
    setState(() => _loading = true);
    try {
      final all = await _service.getMapData();
      final match = all.where((v) => v.id == widget.venueId).firstOrNull;
      if (mounted) setState(() => _venue = match);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      final hist = await _service.getVenueStatusHistory(widget.venueId);
      if (mounted) setState(() => _history = hist);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _navigate() async {
    if (_venue == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${_venue!.lat},${_venue!.lng}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
    if (_loading) {
      return Scaffold(
        appBar: CustomAppBar(title: 'Venue Detail', showBackButton: true),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_venue == null) {
      return Scaffold(
        appBar: CustomAppBar(title: 'Venue Detail', showBackButton: true),
        body: Center(child: Text('Venue not found.', style: AppTypography.bodyMedium)),
      );
    }

    final v = _venue!;
    final statusColor = _colorFor(v.status);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: v.code, showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(v, statusColor),
            const SizedBox(height: 14),
            _buildInfoCard(v),
            if (v.resources.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildChipsCard('Resources', v.resources, Icons.devices_other_outlined, AppColors.accent),
            ],
            if (v.accessibility.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildChipsCard('Accessibility', v.accessibility, Icons.accessible_outlined, AppColors.statusFree),
            ],
            const SizedBox(height: 14),
            _buildMapCard(v),
            const SizedBox(height: 14),
            _buildHistoryCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(VenueMapData v, Color statusColor) {
    return ReusableCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.code, style: AppTypography.headlineLarge.copyWith(color: AppColors.primary)),
            Text(v.name, style: AppTypography.titleMedium),
            Text('${v.buildingName} · Floor ${v.floor}', style: AppTypography.bodySmall),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withAlpha(80)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(v.statusDisplay,
                  style: AppTypography.labelMedium.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildInfoCard(VenueMapData v) {
    return ReusableCard(
      child: Column(children: [
        _infoRow(Icons.people_outline, 'Capacity', '${v.capacity} seats', AppColors.primary),
        const Divider(height: 1),
        _infoRow(Icons.category_outlined, 'Type', v.venueTypeDisplay, AppColors.accent),
        if (v.isAccessible) ...[
          const Divider(height: 1),
          _infoRow(Icons.accessible_outlined, 'Accessible', 'Yes', AppColors.statusFree),
        ],
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        Text(value, style: AppTypography.labelLarge.copyWith(color: AppColors.textMain)),
      ]),
    );
  }

  Widget _buildChipsCard(String title, List<dynamic> items, IconData icon, Color color) {
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(title, style: AppTypography.titleMedium.copyWith(color: color)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.map((r) => Chip(
              label: Text(r.toString().replaceAll('_', ' '),
                  style: AppTypography.caption.copyWith(color: color)),
              backgroundColor: color.withAlpha(12),
              side: BorderSide(color: color.withAlpha(60)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildMapCard(VenueMapData v) {
    final point = LatLng(v.lat, v.lng);
    final color = _colorFor(v.status);

    return ReusableCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      child: Column(children: [
        // Mini map
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: SizedBox(
            height: 160,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 18.5,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ac.tz.utlva.mobile',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        // Navigate button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GPS Location', style: AppTypography.labelLarge),
              Text('${v.lat.toStringAsFixed(6)}, ${v.lng.toStringAsFixed(6)}',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ]),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _navigate,
              icon: const Icon(Icons.directions_outlined, size: 16),
              label: const Text('Navigate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                minimumSize: const Size(0, 36),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildHistoryCard() {
    return ReusableCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Icon(Icons.history, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Status History', style: AppTypography.titleMedium),
          ]),
        ),
        if (_historyLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
          )
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text('No status changes recorded yet.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          )
        else
          ...(_history.take(10).map((h) => _buildHistoryTile(h))),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _buildHistoryTile(VenueStatusHistory h) {
    final color = _colorFor(h.newStatus);
    return ListTile(
      dense: true,
      leading: Container(
        width: 8, height: 8,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        '${h.oldStatus} → ${h.newStatus}',
        style: AppTypography.labelMedium.copyWith(color: AppColors.textMain),
      ),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (h.reason.isNotEmpty) Text(h.reason, style: AppTypography.caption),
        Text(
          '${h.changedByName} · ${_formatDate(h.changedAt)}',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
