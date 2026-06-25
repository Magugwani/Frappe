import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/timetable_entry.dart';
import '../models/generation_result.dart';
import '../models/timetable_conflict.dart';
import '../models/timetable_lifecycle.dart';
import '../models/venue_recommendation.dart';
import '../models/emergency_session.dart';

class TimetableService {
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String get _base => '${AppConfig.baseUrl}/api/timetable';

  Future<List<TimetableEntry>> _getList(String url) async {
    final r = await http.get(Uri.parse(url), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List)
          .map((e) => TimetableEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load timetable: ${r.statusCode}');
  }

  // ── Coordinator: full CRUD ─────────────────────────────────────────────────

  Future<List<TimetableEntry>> getEntries({
    int? academicYearId,
    int? semesterId,
    int? programmeId,
    int? studentGroupId,
    String? status,
  }) {
    final params = <String>[];
    if (academicYearId != null) params.add('academic_year=$academicYearId');
    if (semesterId != null) params.add('semester=$semesterId');
    if (programmeId != null) params.add('programme=$programmeId');
    if (studentGroupId != null) params.add('student_group=$studentGroupId');
    if (status != null) params.add('status=$status');
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/entries/$q');
  }

  Future<TimetableEntry> createEntry(TimetableEntry e) async {
    final r = await http
        .post(Uri.parse('$_base/entries/'), headers: await _headers(), body: jsonEncode(e.toJson()))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 201) return TimetableEntry.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<TimetableEntry> updateEntry(TimetableEntry e) async {
    final r = await http
        .put(Uri.parse('$_base/entries/${e.id}/'), headers: await _headers(), body: jsonEncode(e.toJson()))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return TimetableEntry.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<void> deleteEntry(int id) async {
    final r = await http.delete(Uri.parse('$_base/entries/$id/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 204) throw Exception('Delete failed: ${r.statusCode}');
  }

  // ── Lecturer: my timetable ─────────────────────────────────────────────────

  Future<List<TimetableEntry>> getLecturerTimetable({int? academicYearId, int? semesterId}) {
    final params = <String>[];
    if (academicYearId != null) params.add('academic_year=$academicYearId');
    if (semesterId != null) params.add('semester=$semesterId');
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/entries/my-lecturer-timetable/$q');
  }

  // ── Student: timetable by programme + group ────────────────────────────────

  Future<List<TimetableEntry>> getStudentTimetable({
    required int programmeId,
    int? studentGroupId,
    int? academicYearId,
    int? semesterId,
  }) {
    final params = ['programme=$programmeId'];
    if (studentGroupId != null) params.add('student_group=$studentGroupId');
    if (academicYearId != null) params.add('academic_year=$academicYearId');
    if (semesterId != null) params.add('semester=$semesterId');
    return _getList('$_base/entries/my-student-timetable/?${params.join('&')}');
  }

  // ── Timetable Generation ───────────────────────────────────────────────────

  /// Triggers the automatic timetable generator for the given semester.
  /// Returns a [GenerationResult] with generated/failed counts and details.
  Future<GenerationResult> generateTimetable({
    required int academicYearId,
    required int semesterId,
    required int programmeId,
    bool dryRun = false,
  }) async {
    final body = {
      'academic_year': academicYearId,
      'semester': semesterId,
      'programme': programmeId,
      'dry_run': dryRun,
    };
    final r = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/timetable/generate/'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120)); // generation can take time

    if (r.statusCode == 200) {
      return GenerationResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  // ── Conflict Validation ────────────────────────────────────────────────────

  /// Runs the conflict detection engine for the given semester.
  /// Returns a [ValidationResult] with status PASSED or FAILED, conflict
  /// counts by type, and full conflict details.
  Future<ValidationResult> validateTimetable({
    required int academicYearId,
    required int semesterId,
  }) async {
    final r = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/timetable/validate/'),
          headers: await _headers(),
          body: jsonEncode({'academic_year': academicYearId, 'semester': semesterId}),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 200) {
      return ValidationResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  // ── Lifecycle — Status / Publish / Unpublish ───────────────────────────────

  Future<TimetableStatusInfo> getTimetableStatus({
    required int academicYearId,
    required int semesterId,
  }) async {
    final r = await http.get(
      Uri.parse('${AppConfig.baseUrl}/api/timetable/status/?academic_year=$academicYearId&semester=$semesterId'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      return TimetableStatusInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<PublishResult> publishTimetable({
    required int academicYearId,
    required int semesterId,
  }) async {
    final r = await http.post(
      Uri.parse('${AppConfig.baseUrl}/api/timetable/publish/'),
      headers: await _headers(),
      body: jsonEncode({'academic_year': academicYearId, 'semester': semesterId}),
    ).timeout(const Duration(seconds: 30));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return PublishResult.fromJson(body);
  }

  Future<Map<String, dynamic>> unpublishTimetable({
    required int academicYearId,
    required int semesterId,
  }) async {
    final r = await http.post(
      Uri.parse('${AppConfig.baseUrl}/api/timetable/unpublish/'),
      headers: await _headers(),
      body: jsonEncode({'academic_year': academicYearId, 'semester': semesterId}),
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ── Conflict management ────────────────────────────────────────────────────

  Future<List<ConflictItem>> getConflicts({
    required int semesterId,
    String? status,
  }) async {
    final params = 'semester=$semesterId${status != null ? '&status=$status' : ''}';
    final r = await http.get(
      Uri.parse('${AppConfig.baseUrl}/api/timetable/conflicts/?$params'),
      headers: await _headers(),
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      return list.map((e) => ConflictItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<Map<String, dynamic>> resolveConflict(int conflictId, String resolutionNote) async {
    final r = await http.post(
      Uri.parse('${AppConfig.baseUrl}/api/timetable/conflicts/$conflictId/resolve/'),
      headers: await _headers(),
      body: jsonEncode({'resolution_note': resolutionNote}),
    ).timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ── Phase 8: Venue Recommendations ────────────────────────────────────────

  /// Returns up to 3 suitable venue recommendations for the given slot and
  /// student count. Applies capacity overhead from SystemConfiguration.
  Future<VenueRecommendationResult> getVenueRecommendations({
    required int studentsCount,
    required String dayOfWeek,
    required String startTime,
    required String endTime,
    String? venueType,
    List<String>? requiredResources,
    int? semesterId,
  }) async {
    final body = <String, dynamic>{
      'students_count': studentsCount,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      if (venueType != null) 'venue_type': venueType,
      if (requiredResources != null && requiredResources.isNotEmpty)
        'required_resources': requiredResources,
      if (semesterId != null) 'semester': semesterId,
    };
    final r = await http
        .post(
          Uri.parse('$_base/venue-recommendations/'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      return VenueRecommendationResult.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  // ── Phase 8: Emergency Sessions ───────────────────────────────────────────

  Future<List<EmergencySession>> getEmergencySessions({String? status}) async {
    final q = status != null ? '?status=$status' : '';
    final r = await http
        .get(
          Uri.parse('${AppConfig.baseUrl}/api/sessions/emergency/$q'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List)
          .map((e) => EmergencySession.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<EmergencySession> createEmergencySession({
    required int courseId,
    required int lecturerId,
    required String requestedDate,
    required String dayOfWeek,
    required String startTime,
    required String endTime,
    required String reason,
    int? venueId,
    List<int>? studentGroupIds,
  }) async {
    final body = <String, dynamic>{
      'course': courseId,
      'lecturer': lecturerId,
      'requested_date': requestedDate,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'reason': reason,
      if (venueId != null) 'venue': venueId,
      if (studentGroupIds != null && studentGroupIds.isNotEmpty)
        'student_groups': studentGroupIds,
    };
    final r = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/sessions/emergency/'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 201) {
      return EmergencySession.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<Map<String, dynamic>> approveEmergencySession(int id, String note) async {
    final r = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/sessions/emergency/$id/approve/'),
          headers: await _headers(),
          body: jsonEncode({'note': note}),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectEmergencySession(int id, String note) async {
    final r = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/sessions/emergency/$id/reject/'),
          headers: await _headers(),
          body: jsonEncode({'note': note}),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
