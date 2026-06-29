import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/venue_models.dart';
import '../services/venues_service.dart';

class VenueStatusScreen extends StatefulWidget {
  const VenueStatusScreen({super.key});

  @override
  State<VenueStatusScreen> createState() => _VenueStatusScreenState();
}

class _VenueStatusScreenState extends State<VenueStatusScreen> {
  final _service = VenuesService();
  List<Venue> _venues = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  Future<void> _loadVenues() async {
    setState(() { _loading = true; _error = null; });
    try {
      final venues = await _service.getVenues();
      if (mounted) setState(() => _venues = venues.where((v) => v.isActive).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role ?? '';
    final canUpdate = role == 'COORDINATOR' || role == 'SYSTEM_ADMIN';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Venue Status Monitor', showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadVenues,
                  child: _venues.isEmpty
                      ? const Center(child: Text('No active venues found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _venues.length,
                          itemBuilder: (context, i) => _VenueStatusCard(
                            venue: _venues[i],
                            canUpdate: canUpdate,
                            service: _service,
                            onUpdated: _loadVenues,
                          ),
                        ),
                ),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
      const SizedBox(height: 12),
      Text('Failed to load venues', style: AppTypography.titleMedium),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _loadVenues, child: const Text('Retry')),
    ]),
  );
}

// ── Venue Status Card ─────────────────────────────────────────────────────────

class _VenueStatusCard extends StatefulWidget {
  final Venue venue;
  final bool canUpdate;
  final VenuesService service;
  final VoidCallback onUpdated;

  const _VenueStatusCard({
    required this.venue,
    required this.canUpdate,
    required this.service,
    required this.onUpdated,
  });

  @override
  State<_VenueStatusCard> createState() => _VenueStatusCardState();
}

class _VenueStatusCardState extends State<_VenueStatusCard> {
  bool _expanded = false;
  List<VenueStatusHistory>? _history;
  bool _loadingHistory = false;
  bool _updatingStatus = false;

  String _newStatus = '';
  final _reasonController = TextEditingController();

  static const _statusChoices = [
    'FREE', 'BOOKED', 'IN_USE', 'EXPIRED', 'MAINTENANCE',
  ];

  @override
  void initState() {
    super.initState();
    _newStatus = widget.venue.status;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'FREE': return AppColors.statusFree;
      case 'BOOKED': return AppColors.statusBooked;
      case 'IN_USE': return AppColors.statusInUse;
      case 'EXPIRED': return AppColors.statusExpired;
      default: return AppColors.textSecondary;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'FREE': return 'Free';
      case 'BOOKED': return 'Booked';
      case 'IN_USE': return 'In Use';
      case 'EXPIRED': return 'Expired';
      case 'MAINTENANCE': return 'Maintenance';
      default: return s;
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final history = await widget.service.getVenueStatusHistory(widget.venue.id);
      if (mounted) setState(() => _history = history);
    } catch (_) {
      if (mounted) setState(() => _history = []);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _updateStatus() async {
    if (_newStatus == widget.venue.status) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Status unchanged.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    setState(() => _updatingStatus = true);
    try {
      await widget.service.updateVenueStatus(
          widget.venue.id, _newStatus, _reasonController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Status updated.'),
          backgroundColor: AppColors.statusFree,
          behavior: SnackBarBehavior.floating,
        ));
        widget.onUpdated();
        setState(() { _history = null; }); // reload history on next expand
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final statusColor = _statusColor(venue.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        // Header
        ListTile(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _history == null) _loadHistory();
          },
          leading: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.meeting_room_outlined, color: statusColor),
          ),
          title: Text(venue.code, style: AppTypography.titleMedium),
          subtitle: Text(venue.name, style: AppTypography.bodySmall),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _StatusChip(label: _statusLabel(venue.status), color: statusColor),
            const SizedBox(width: 4),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: AppColors.textSecondary),
          ]),
        ),

        // Expanded details
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Venue info
              Row(children: [
                const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Capacity: ${venue.capacity}', style: AppTypography.bodySmall),
                const SizedBox(width: 16),
                const Icon(Icons.category_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(venue.venueTypeDisplay, style: AppTypography.bodySmall),
              ]),

              // Update status section (coordinator/admin only)
              if (widget.canUpdate) ...[
                const SizedBox(height: 16),
                Text('Update Status', style: AppTypography.titleMedium.copyWith(color: AppColors.accent)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _newStatus,
                  decoration: const InputDecoration(labelText: 'New Status'),
                  items: _statusChoices.map((s) => DropdownMenuItem(
                    value: s,
                    child: Row(children: [
                      Container(
                        width: 10, height: 10,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _statusColor(s),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(_statusLabel(s)),
                    ]),
                  )).toList(),
                  onChanged: (v) => setState(() => _newStatus = v!),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'Reason for status change...',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _updatingStatus ? null : _updateStatus,
                    child: _updatingStatus
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(
                                color: AppColors.textOnPrimary, strokeWidth: 2))
                        : const Text('Update Status'),
                  ),
                ),
              ],

              // Status history
              const SizedBox(height: 16),
              Text('Status History', style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const Center(child: CircularProgressIndicator(color: AppColors.primary))
              else if (_history == null || _history!.isEmpty)
                Text('No status history available.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))
              else
                Column(
                  children: _history!.take(5).map((h) => _HistoryTile(h: h)).toList(),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── History Tile ──────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final VenueStatusHistory h;
  const _HistoryTile({required this.h});

  Color _color(String s) {
    switch (s) {
      case 'FREE': return AppColors.statusFree;
      case 'BOOKED': return AppColors.statusBooked;
      case 'IN_USE': return AppColors.statusInUse;
      case 'EXPIRED': return AppColors.statusExpired;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.swap_horiz, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _StatusChip(label: h.oldStatusDisplay, color: _color(h.oldStatus), small: true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 12, color: AppColors.textSecondary),
              ),
              _StatusChip(label: h.newStatusDisplay, color: _color(h.newStatus), small: true),
            ]),
            const SizedBox(height: 2),
            Text(
              '${h.changedByName ?? 'Unknown'} — ${_formatDate(h.changedAt)}',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
            if (h.reason.isNotEmpty)
              Text(h.reason,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;
  const _StatusChip({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: (small ? AppTypography.caption : AppTypography.labelMedium)
            .copyWith(color: color),
      ),
    );
  }
}
