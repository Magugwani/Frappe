import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';

class BulkEnrollmentResult {
  final int jobId;
  final String status;
  final String role;
  final String mode;
  final String filename;
  final int totalRows;
  final int validRows;
  final int createdRows;
  final int skippedRows;
  final int errorCount;
  final bool hasErrors;
  final String? errorReportUrl;
  final String message;

  const BulkEnrollmentResult({
    required this.jobId,
    required this.status,
    required this.role,
    required this.mode,
    required this.filename,
    required this.totalRows,
    required this.validRows,
    required this.createdRows,
    required this.skippedRows,
    required this.errorCount,
    required this.hasErrors,
    this.errorReportUrl,
    required this.message,
  });

  factory BulkEnrollmentResult.fromJson(Map<String, dynamic> j) =>
      BulkEnrollmentResult(
        jobId: j['job_id'] as int? ?? 0,
        status: j['status'] as String? ?? '',
        role: j['role'] as String? ?? '',
        mode: j['mode'] as String? ?? '',
        filename: j['filename'] as String? ?? '',
        totalRows: j['total_rows'] as int? ?? 0,
        validRows: j['valid_rows'] as int? ?? 0,
        createdRows: j['created_rows'] as int? ?? 0,
        skippedRows: j['skipped_rows'] as int? ?? 0,
        errorCount: j['error_count'] as int? ?? 0,
        hasErrors: j['has_errors'] as bool? ?? false,
        errorReportUrl: j['error_report_url'] as String?,
        message: j['message'] as String? ?? '',
      );

  bool get isSuccess => status == 'COMPLETED' && createdRows > 0;
  bool get isFailed => status == 'FAILED';
  bool get isRejected => hasErrors && createdRows == 0;
}

class BulkEnrollmentJob {
  final int id;
  final String role;
  final String status;
  final String filename;
  final int totalRows;
  final int createdRows;
  final int errorCount;
  final String createdAt;

  const BulkEnrollmentJob({
    required this.id,
    required this.role,
    required this.status,
    required this.filename,
    required this.totalRows,
    required this.createdRows,
    required this.errorCount,
    required this.createdAt,
  });

  factory BulkEnrollmentJob.fromJson(Map<String, dynamic> j) =>
      BulkEnrollmentJob(
        id: j['id'] as int? ?? 0,
        role: j['role'] as String? ?? '',
        status: j['status'] as String? ?? '',
        filename: j['filename'] as String? ?? '',
        totalRows: j['total_rows'] as int? ?? 0,
        createdRows: j['created_rows'] as int? ?? 0,
        errorCount: j['error_count'] as int? ?? 0,
        createdAt: j['created_at'] as String? ?? '',
      );
}

class BulkEnrollmentService {
  final AuthService _auth = AuthService();

  String get _base => '${AppConfig.baseUrl}/api/accounts/bulk-enroll';

  Future<Map<String, String>> _authHeaders() async {
    final token = await _auth.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// FR-52/53: Upload a CSV file for bulk enrollment.
  /// [role] = 'STUDENT' or 'LECTURER'
  /// [mode] = 'REJECT_ALL' (default) | 'IMPORT_VALID'
  Future<BulkEnrollmentResult> uploadCSV({
    required List<int> fileBytes,
    required String filename,
    required String role,
    String mode = 'REJECT_ALL',
  }) async {
    final headers = await _authHeaders();
    final request = http.MultipartRequest('POST', Uri.parse('$_base/'));
    request.headers.addAll(Map<String, String>.from(headers));
    request.fields['role'] = role;
    request.fields['mode'] = mode;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200 || streamed.statusCode == 201) {
      return BulkEnrollmentResult.fromJson(
          jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Upload failed (${streamed.statusCode}): $body');
  }

  /// List recent enrollment jobs for this user.
  Future<List<BulkEnrollmentJob>> listJobs() async {
    final r = await http
        .get(Uri.parse('$_base/'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as List;
      return data.map((j) => BulkEnrollmentJob.fromJson(j as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to list jobs: ${r.statusCode}');
  }

  /// Get the full URL for downloading a CSV error report.
  String errorReportUrl(int jobId) => '$_base/$jobId/error-report/';

  /// Get the full URL for downloading the blank CSV template.
  String templateUrl(String role) =>
      '$_base/template/${role.toUpperCase()}/';
}
