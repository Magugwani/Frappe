import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/venue_models.dart';
import '../services/venues_service.dart';

class VenueScreen extends StatefulWidget {
  const VenueScreen({super.key});
  @override
  State<VenueScreen> createState() => _VenueScreenState();
}

class _VenueScreenState extends State<VenueScreen> {
  final _service = VenuesService();
  List<Venue> _items = [];
  List<Building> _buildings = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load independently so a venues error never blocks the buildings dropdown.
      final results = await Future.wait([
        _service.getVenues().catchError((_) => <Venue>[]),
        _service.getBuildings().catchError((_) => <Building>[]),
      ]);
      if (mounted) {
        _items     = results[0] as List<Venue>;
        _buildings = results[1] as List<Building>;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) => switch (status) {
    'FREE' => AppColors.statusFree,
    'BOOKED' => AppColors.statusBooked,
    'IN_USE' => AppColors.statusInUse,
    'EXPIRED' => AppColors.statusExpired,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Venues')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No venues yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final v = _items[i];
                    return ManagementTile(
                      title: '${v.code} — ${v.name}',
                      subtitle: '${v.buildingName} | Floor ${v.floor} | Cap: ${v.capacity} | ${v.venueTypeDisplay}',
                      badge: v.status, badgeColor: _statusColor(v.status),
                      icon: Icons.meeting_room_outlined, iconColor: AppColors.primary,
                      onEdit: () => _showForm(context, venue: v),
                      onDelete: () => _delete(v),
                    );
                  })),
    );
  }

  Future<void> _delete(Venue v) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Venue'), content: Text('Delete "${v.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteVenue(v.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {Venue? venue}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _VenueForm(venue: venue, buildings: _buildings, onSaved: (v) async { Navigator.pop(ctx); try { venue == null ? await _service.createVenue(v) : await _service.updateVenue(v); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }));
  }
}

class _VenueForm extends StatefulWidget {
  final Venue? venue;
  final List<Building> buildings;
  final Future<void> Function(Venue) onSaved;
  const _VenueForm({this.venue, required this.buildings, required this.onSaved});
  @override
  State<_VenueForm> createState() => _VenueFormState();
}

class _VenueFormState extends State<_VenueForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code, _name, _capacity;
  int? _buildingId;
  int _floor = 0;
  String _venueType = 'CLASSROOM';
  bool _saving = false;

  static const _venueTypes = ['CLASSROOM', 'LECTURE_HALL', 'COMPUTER_LAB', 'LABORATORY', 'SEMINAR_ROOM', 'AUDITORIUM'];

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.venue?.code ?? '');
    _name = TextEditingController(text: widget.venue?.name ?? '');
    _capacity = TextEditingController(text: widget.venue?.capacity.toString() ?? '');
    _buildingId = widget.venue?.buildingId ?? (widget.buildings.isNotEmpty ? widget.buildings.first.id : null);
    _floor = widget.venue?.floor ?? 0;
    _venueType = widget.venue?.venueType ?? 'CLASSROOM';
  }

  @override
  void dispose() { _code.dispose(); _name.dispose(); _capacity.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _buildingId == null) return;
    setState(() => _saving = true);
    await widget.onSaved(Venue(id: widget.venue?.id ?? 0, code: _code.text.trim().toUpperCase(), name: _name.text.trim(), buildingId: _buildingId!, buildingName: '', floor: _floor, capacity: int.tryParse(_capacity.text) ?? 0, venueType: _venueType, venueTypeDisplay: _venueType, resources: [], accessibility: [], status: widget.venue?.status ?? 'FREE', statusDisplay: 'Free', isActive: true));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.venue == null ? 'New Venue' : 'Edit Venue', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Venue Code (e.g. LH-A101)'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Venue Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _buildingId, decoration: const InputDecoration(labelText: 'Building'), items: widget.buildings.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _buildingId = v), validator: (v) => v == null ? 'Required' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(value: _floor, decoration: const InputDecoration(labelText: 'Floor'), items: List.generate(10, (i) => DropdownMenuItem(value: i, child: Text(i == 0 ? 'Ground' : 'Floor $i'))).toList(), onChanged: (v) => setState(() => _floor = v!))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _capacity, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Required' : null)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _venueType, decoration: const InputDecoration(labelText: 'Venue Type'), items: _venueTypes.map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(), onChanged: (v) => setState(() => _venueType = v!)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.venue == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
