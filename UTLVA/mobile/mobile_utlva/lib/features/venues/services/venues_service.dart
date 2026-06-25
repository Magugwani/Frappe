import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/venue_models.dart';
import '../models/venue_map_data.dart';

class VenuesService {
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String get _base => '${AppConfig.baseUrl}/api/venues';

  Future<List<T>> _getList<T>(String url, T Function(Map<String, dynamic>) fromJson) async {
    final r = await http.get(Uri.parse(url), headers: await _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load: ${r.statusCode}');
  }

  Future<T> _post<T>(String url, Map<String, dynamic> body, T Function(Map<String, dynamic>) fromJson) async {
    final r = await http.post(Uri.parse(url), headers: await _headers(), body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    if (r.statusCode == 201) return fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<T> _put<T>(String url, Map<String, dynamic> body, T Function(Map<String, dynamic>) fromJson) async {
    final r = await http.put(Uri.parse(url), headers: await _headers(), body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<void> _delete(String url) async {
    final r = await http.delete(Uri.parse(url), headers: await _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode != 204) throw Exception('Delete failed: ${r.statusCode}');
  }

  // ── Buildings ──────────────────────────────────────────────────────────────

  Future<List<Building>> getBuildings() => _getList('$_base/buildings/', Building.fromJson);
  Future<Building> createBuilding(Building b) => _post('$_base/buildings/', b.toJson(), Building.fromJson);
  Future<Building> updateBuilding(Building b) => _put('$_base/buildings/${b.id}/', b.toJson(), Building.fromJson);
  Future<void> deleteBuilding(int id) => _delete('$_base/buildings/$id/');

  // ── Venues ─────────────────────────────────────────────────────────────────

  Future<List<Venue>> getVenues({int? buildingId, String? venueType}) {
    final params = <String>[];
    if (buildingId != null) params.add('building=$buildingId');
    if (venueType != null) params.add('venue_type=$venueType');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/venues/$query', Venue.fromJson);
  }

  Future<Venue> createVenue(Venue v) => _post('$_base/venues/', v.toJson(), Venue.fromJson);
  Future<Venue> updateVenue(Venue v) => _put('$_base/venues/${v.id}/', v.toJson(), Venue.fromJson);
  Future<void> deleteVenue(int id) => _delete('$_base/venues/$id/');

  // ── Phase 8: Venue Status ──────────────────────────────────────────────────

  /// Returns the status change history for a venue.
  Future<List<VenueStatusHistory>> getVenueStatusHistory(int venueId) =>
      _getList('$_base/venues/$venueId/status-history/', VenueStatusHistory.fromJson);

  /// Updates the status of a venue and records the change in VenueStatusHistory.
  Future<Map<String, dynamic>> updateVenueStatus(
      int venueId, String newStatus, String reason) async {
    final r = await http
        .post(
          Uri.parse('$_base/venues/$venueId/update-status/'),
          headers: await _headers(),
          body: jsonEncode({'new_status': newStatus, 'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  // ── Phase 9: Map data + deactivation ──────────────────────────────────────

  /// Lightweight list of all active venues with resolved GPS coordinates.
  /// Venues without coordinates (no venue lat/lng AND no building lat/lng) are omitted.
  Future<List<VenueMapData>> getMapData() async {
    final r = await http
        .get(Uri.parse('$_base/venues/map-data/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      return list.map((e) => VenueMapData.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load map data: ${r.statusCode}');
  }

  /// Deactivate a venue. If blocking timetable entries exist and [force] is
  /// false, returns a 422 with the blocking entries list (check response).
  Future<Map<String, dynamic>> deactivateVenue(int id, {bool force = false}) async {
    final r = await http
        .post(
          Uri.parse('$_base/venues/$id/deactivate/'),
          headers: await _headers(),
          body: jsonEncode({'force': force}),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Reactivate a previously deactivated venue.
  Future<Map<String, dynamic>> reactivateVenue(int id) async {
    final r = await http
        .post(Uri.parse('$_base/venues/$id/reactivate/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Filtered venue list for the venue browser.
  Future<List<Venue>> searchVenues({
    int? buildingId,
    String? venueType,
    String? status,
    int? minCapacity,
    int? maxCapacity,
    bool? accessible,
    String? search,
    bool activeOnly = true,
  }) {
    final params = <String>[];
    if (buildingId != null) params.add('building=$buildingId');
    if (venueType != null) params.add('venue_type=$venueType');
    if (status != null) params.add('status=$status');
    if (minCapacity != null) params.add('min_capacity=$minCapacity');
    if (maxCapacity != null) params.add('max_capacity=$maxCapacity');
    if (accessible == true) params.add('accessible=true');
    if (search != null && search.isNotEmpty) params.add('search=$search');
    if (activeOnly) params.add('is_active=true');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/venues/$query', Venue.fromJson);
  }
}
