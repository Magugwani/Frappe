import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/venue_models.dart';

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
}
