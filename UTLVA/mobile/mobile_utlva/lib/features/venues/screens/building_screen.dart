import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/management_list_screen.dart';
import '../models/venue_models.dart';
import '../services/venues_service.dart';

class BuildingScreen extends StatefulWidget {
  const BuildingScreen({super.key});
  @override
  State<BuildingScreen> createState() => _BuildingScreenState();
}

class _BuildingScreenState extends State<BuildingScreen> {
  final _service = VenuesService();
  List<Building> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _items = await _service.getBuildings(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.secondary, foregroundColor: AppColors.textOnPrimary, title: const Text('Buildings')),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: AppColors.textOnPrimary), onPressed: () => _showForm(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(onRefresh: _load, child: _items.isEmpty
              ? const Center(child: Text('No buildings yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = _items[i];
                    return ManagementTile(
                      title: b.name,
                      subtitle: b.address.isEmpty ? 'No address' : b.address,
                      badge: '${b.venueCount} venue${b.venueCount != 1 ? 's' : ''}',
                      badgeColor: AppColors.statusFree,
                      icon: Icons.business_outlined, iconColor: AppColors.primary,
                      onEdit: () => _showForm(context, building: b),
                      onDelete: () => _delete(b),
                    );
                  })),
    );
  }

  Future<void> _delete(Building b) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete Building'), content: Text('Delete "${b.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppColors.error)))]));
    if (ok == true) { try { await _service.deleteBuilding(b.id); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }
  }

  void _showForm(BuildContext context, {Building? building}) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BuildingForm(building: building, onSaved: (b) async { Navigator.pop(ctx); try { building == null ? await _service.createBuilding(b) : await _service.updateBuilding(b); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error)); } }));
  }
}

class _BuildingForm extends StatefulWidget {
  final Building? building;
  final Future<void> Function(Building) onSaved;
  const _BuildingForm({this.building, required this.onSaved});
  @override
  State<_BuildingForm> createState() => _BuildingFormState();
}

class _BuildingFormState extends State<_BuildingForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _address, _lat, _lng;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.building?.name ?? '');
    _address = TextEditingController(text: widget.building?.address ?? '');
    _lat = TextEditingController(text: widget.building?.latitude?.toString() ?? '');
    _lng = TextEditingController(text: widget.building?.longitude?.toString() ?? '');
  }

  @override
  void dispose() { _name.dispose(); _address.dispose(); _lat.dispose(); _lng.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.onSaved(Building(id: widget.building?.id ?? 0, name: _name.text.trim(), address: _address.text.trim(), latitude: double.tryParse(_lat.text), longitude: double.tryParse(_lng.text), venueCount: 0));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.building == null ? 'New Building' : 'Edit Building', style: AppTypography.headlineMedium),
        const SizedBox(height: 20),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Building Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _lat, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _lng, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
        ]),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(widget.building == null ? 'Create' : 'Save'))),
      ])),
    );
  }
}
