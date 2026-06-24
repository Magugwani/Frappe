import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/academic_models.dart';
import '../models/student_profile.dart';

class AcademicsService {
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String get _base => '${AppConfig.baseUrl}/api/academics';

  // ── Generic helpers ────────────────────────────────────────────────────────

  Future<List<T>> _getList<T>(String url, T Function(Map<String, dynamic>) fromJson) async {
    final r = await http.get(Uri.parse(url), headers: await _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load data: ${r.statusCode}');
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

  // ── Academic Years ─────────────────────────────────────────────────────────

  Future<List<AcademicYear>> getYears() => _getList('$_base/years/', AcademicYear.fromJson);
  Future<AcademicYear> createYear(AcademicYear y) => _post('$_base/years/', y.toJson(), AcademicYear.fromJson);
  Future<AcademicYear> updateYear(AcademicYear y) => _put('$_base/years/${y.id}/', y.toJson(), AcademicYear.fromJson);
  Future<void> deleteYear(int id) => _delete('$_base/years/$id/');

  // ── Semesters ──────────────────────────────────────────────────────────────

  Future<List<Semester>> getSemesters({int? yearId}) =>
      _getList('$_base/semesters/${yearId != null ? '?academic_year=$yearId' : ''}', Semester.fromJson);
  Future<Semester> createSemester(Semester s) => _post('$_base/semesters/', s.toJson(), Semester.fromJson);
  Future<Semester> updateSemester(Semester s) => _put('$_base/semesters/${s.id}/', s.toJson(), Semester.fromJson);
  Future<void> deleteSemester(int id) => _delete('$_base/semesters/$id/');

  // ── Departments ────────────────────────────────────────────────────────────

  Future<List<Department>> getDepartments() => _getList('$_base/departments/', Department.fromJson);
  Future<Department> createDepartment(Department d) => _post('$_base/departments/', d.toJson(), Department.fromJson);
  Future<Department> updateDepartment(Department d) => _put('$_base/departments/${d.id}/', d.toJson(), Department.fromJson);
  Future<void> deleteDepartment(int id) => _delete('$_base/departments/$id/');

  // ── Programmes ─────────────────────────────────────────────────────────────

  Future<List<Programme>> getProgrammes({int? deptId}) =>
      _getList('$_base/programmes/${deptId != null ? '?department=$deptId' : ''}', Programme.fromJson);
  Future<Programme> createProgramme(Programme p) => _post('$_base/programmes/', p.toJson(), Programme.fromJson);
  Future<Programme> updateProgramme(Programme p) => _put('$_base/programmes/${p.id}/', p.toJson(), Programme.fromJson);
  Future<void> deleteProgramme(int id) => _delete('$_base/programmes/$id/');

  // ── Student Groups ─────────────────────────────────────────────────────────

  Future<List<StudentGroup>> getGroups({int? programmeId}) =>
      _getList('$_base/groups/${programmeId != null ? '?programme=$programmeId' : ''}', StudentGroup.fromJson);
  Future<StudentGroup> createGroup(StudentGroup g) => _post('$_base/groups/', g.toJson(), StudentGroup.fromJson);
  Future<StudentGroup> updateGroup(StudentGroup g) => _put('$_base/groups/${g.id}/', g.toJson(), StudentGroup.fromJson);
  Future<void> deleteGroup(int id) => _delete('$_base/groups/$id/');

  // ── Courses ────────────────────────────────────────────────────────────────

  Future<List<Course>> getCourses({int? programmeId, int? semesterId}) {
    final params = <String>[];
    if (programmeId != null) params.add('programme=$programmeId');
    if (semesterId != null) params.add('semester=$semesterId');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/courses/$query', Course.fromJson);
  }

  Future<Course> createCourse(Course c) => _post('$_base/courses/', c.toJson(), Course.fromJson);
  Future<Course> updateCourse(Course c) => _put('$_base/courses/${c.id}/', c.toJson(), Course.fromJson);
  Future<void> deleteCourse(int id) => _delete('$_base/courses/$id/');

  // ── Lecturers ──────────────────────────────────────────────────────────────

  Future<List<Lecturer>> getLecturers({int? deptId}) =>
      _getList('$_base/lecturers/${deptId != null ? '?department=$deptId' : ''}', Lecturer.fromJson);
  Future<Lecturer> createLecturer(Lecturer l) => _post('$_base/lecturers/', l.toJson(), Lecturer.fromJson);
  Future<Lecturer> updateLecturer(Lecturer l) => _put('$_base/lecturers/${l.id}/', l.toJson(), Lecturer.fromJson);
  Future<void> deleteLecturer(int id) => _delete('$_base/lecturers/$id/');

  Future<void> assignCourse(int lecturerId, int courseId, {int? academicYearId}) async {
    final body = <String, dynamic>{'course_id': courseId};
    if (academicYearId != null) body['academic_year_id'] = academicYearId;
    final r = await http.post(
      Uri.parse('$_base/lecturers/$lecturerId/assign-course/'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception(jsonDecode(r.body).toString());
  }

  Future<void> removeCourseAssignment(int lecturerId, int assignmentId) =>
      _delete('$_base/lecturers/$lecturerId/remove-course/$assignmentId/');

  // ── Teaching Periods ───────────────────────────────────────────────────────

  Future<List<TeachingPeriod>> getTeachingPeriods({int? semesterId, String? dayOfWeek, int? academicYearId}) {
    final params = <String>[];
    if (semesterId != null) params.add('semester=$semesterId');
    if (dayOfWeek != null) params.add('day_of_week=$dayOfWeek');
    if (academicYearId != null) params.add('academic_year=$academicYearId');
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    return _getList('$_base/teaching-periods/$q', TeachingPeriod.fromJson);
  }

  Future<TeachingPeriod> createTeachingPeriod(TeachingPeriod p) =>
      _post('$_base/teaching-periods/', p.toJson(), TeachingPeriod.fromJson);

  Future<TeachingPeriod> updateTeachingPeriod(TeachingPeriod p) =>
      _put('$_base/teaching-periods/${p.id}/', p.toJson(), TeachingPeriod.fromJson);

  Future<void> deleteTeachingPeriod(int id) =>
      _delete('$_base/teaching-periods/$id/');

  // ── Student Profile ────────────────────────────────────────────────────────

  /// Fetch the calling student's own profile. Returns null if none exists yet.
  Future<StudentProfile?> getMyStudentProfile() async {
    try {
      final r = await http
          .get(Uri.parse('$_base/student-profiles/me/'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        return StudentProfile.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return null; // 404 = no profile yet
    } catch (_) {
      return null;
    }
  }

  Future<StudentProfile> createStudentProfile(StudentProfile p) =>
      _post('$_base/student-profiles/', p.toJson(), StudentProfile.fromJson);

  Future<StudentProfile> updateStudentProfile(StudentProfile p) =>
      _put('$_base/student-profiles/me/update/', p.toJson(), StudentProfile.fromJson);
}
