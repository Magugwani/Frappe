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

  // ── Session lifecycle (SRS 3.2/3.4 — FR-26, FR-27, FR-29, FR-33, FR-35) ──

  /// Lecturer confirms session is starting → venue BOOKED → IN_USE.
  Future<Map<String, dynamic>> confirmSession(int entryId) async {
    final r = await http
        .post(Uri.parse('$_base/entries/$entryId/confirm/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Marks session as ended → venue IN_USE → FREE.
  Future<Map<String, dynamic>> endSession(int entryId) async {
    final r = await http
        .post(Uri.parse('$_base/entries/$entryId/end-session/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// SRS §3.12: Cancel a session — supports both BOOKED (pre-start) and
  /// IN_USE (mid-session) venues. Students are notified automatically.
  Future<Map<String, dynamic>> cancelSession(int entryId) async {
    final r = await http
        .post(Uri.parse('$_base/entries/$entryId/cancel/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// FR-33/FR-35: Returns the SessionConfirmation status for a specific entry+date.
  /// If [date] is null, uses today's date.
  Future<Map<String, dynamic>> getConfirmationStatus(int entryId, {String? date}) async {
    final q = date != null ? '?date=$date' : '';
    final r = await http
        .get(
          Uri.parse('$_base/entries/$entryId/confirmation-status/$q'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception('Failed to load confirmation status: ${r.statusCode}');
  }

  /// Postpone one occurrence to a new date/time/venue (FR-26, FR-27).
  Future<Map<String, dynamic>> postponeSession({
    required int entryId,
    required String newDate,
    required String newDayOfWeek,
    required String newStartTime,
    required String newEndTime,
    required String reason,
    int? newVenueId,
  }) async {
    final body = <String, dynamic>{
      'new_date': newDate,
      'new_day_of_week': newDayOfWeek,
      'new_start_time': newStartTime,
      'new_end_time': newEndTime,
      'reason': reason,
      if (newVenueId != null) 'new_venue': newVenueId,
    };
    final r = await http
        .post(
          Uri.parse('$_base/entries/$entryId/postpone/'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// FR-20: Returns courses assigned to the authenticated lecturer.
  Future<List<dynamic>> getLecturerCourses() async {
    final r = await http
        .get(
          Uri.parse('${AppConfig.baseUrl}/api/academics/lecturers/my-courses/'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data['courses'] as List<dynamic>? ?? [];
    }
    throw Exception('Failed to load courses: ${r.statusCode}');
  }

  // ── FR-42: Student view of approved emergency sessions ────────────────────

  /// Returns APPROVED emergency sessions relevant to the authenticated student's
  /// student group. Backend filters automatically based on the user's role.
  Future<List<EmergencySession>> getStudentEmergencySessions() =>
      getEmergencySessions();

  // ── FR-37: Next upcoming class for the student ────────────────────────────

  /// Returns the next PUBLISHED timetable entry for the student's group
  /// occurring today or in future days of the current week.
  Future<Map<String, dynamic>?> getNextClass({
    required int programmeId,
    int? studentGroupId,
  }) async {
    final params = ['programme=$programmeId', 'status=PUBLISHED'];
    if (studentGroupId != null) params.add('student_group=$studentGroupId');
    final r = await http
        .get(Uri.parse('$_base/entries/?${params.join('&')}'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final data = jsonDecode(r.body);
    final list = data is List ? data : (data['results'] ?? data);
    if ((list as List).isEmpty) return null;

    // Days ordered Mon→Sat; pick the next upcoming entry relative to now
    const dayOrder = {
      'MONDAY': 0, 'TUESDAY': 1, 'WEDNESDAY': 2, 'THURSDAY': 3,
      'FRIDAY': 4, 'SATURDAY': 5, 'SUNDAY': 6,
    };
    final now = DateTime.now();
    final todayIdx = now.weekday - 1; // 0=Mon
    final nowTime = now.hour * 60 + now.minute;

    Map<String, dynamic>? best;
    int bestScore = 99999;

    for (final e in list) {
      final entryMap = e as Map<String, dynamic>;
      final dayStr = (entryMap['day_of_week'] as String?) ?? '';
      final dayIdx = dayOrder[dayStr] ?? 99;
      final timeParts = ((entryMap['start_time'] as String?) ?? '00:00').split(':');
      final entryMins = int.parse(timeParts[0]) * 60 + int.parse(timeParts[1]);

      // Score: how many minutes from now (across the week)
      int score;
      if (dayIdx > todayIdx) {
        score = (dayIdx - todayIdx) * 1440 + entryMins;
      } else if (dayIdx == todayIdx && entryMins > nowTime) {
        score = entryMins - nowTime;
      } else {
        continue; // already passed
      }
      if (score < bestScore) { bestScore = score; best = entryMap; }
    }
    return best;
  }

  // ── System configuration (admin only) ─────────────────────────────────────

  Future<Map<String, dynamic>> getSystemConfig() async {
    final r = await http
        .get(Uri.parse('${AppConfig.baseUrl}/api/system/config/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception('Failed to load system config');
  }

  Future<Map<String, dynamic>> updateSystemConfig(Map<String, dynamic> data) async {
    final r = await http
        .patch(
          Uri.parse('${AppConfig.baseUrl}/api/system/config/'),
          headers: await _headers(),
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception(jsonDecode(r.body).toString());
  }
}
