class GeneratedEntry {
  final String courseCode;
  final String courseName;
  final String group;
  final String lecturer;
  final String venue;
  final String day;
  final String time;
  final String session;  // e.g. "1/2"
  final int? entryId;

  const GeneratedEntry({
    required this.courseCode,
    required this.courseName,
    required this.group,
    required this.lecturer,
    required this.venue,
    required this.day,
    required this.time,
    required this.session,
    this.entryId,
  });

  factory GeneratedEntry.fromJson(Map<String, dynamic> j) => GeneratedEntry(
        courseCode: j['course_code'] ?? '',
        courseName: j['course_name'] ?? '',
        group: j['group'] ?? '',
        lecturer: j['lecturer'] ?? '',
        venue: j['venue'] ?? '',
        day: j['day'] ?? '',
        time: j['time'] ?? '',
        session: j['session'] ?? '1/1',
        entryId: j['entry_id'],
      );
}

class FailedEntry {
  final String courseCode;
  final String courseName;
  final String group;
  final String session;
  final String reason;

  const FailedEntry({
    required this.courseCode,
    required this.courseName,
    required this.group,
    required this.session,
    required this.reason,
  });

  factory FailedEntry.fromJson(Map<String, dynamic> j) => FailedEntry(
        courseCode: j['course_code'] ?? '',
        courseName: j['course_name'] ?? '',
        group: j['group'] ?? '',
        session: j['session'] ?? '1/1',
        reason: j['reason'] ?? '',
      );
}

class GenerationResult {
  final String academicYear;
  final String semester;
  final String programme;
  final bool dryRun;
  final int generatedSessions;
  final int failedSessions;
  final List<GeneratedEntry> generated;
  final List<FailedEntry> failed;

  const GenerationResult({
    required this.academicYear,
    required this.semester,
    required this.programme,
    required this.dryRun,
    required this.generatedSessions,
    required this.failedSessions,
    required this.generated,
    required this.failed,
  });

  factory GenerationResult.fromJson(Map<String, dynamic> j) {
    final details = j['details'] as Map<String, dynamic>? ?? {};
    return GenerationResult(
      academicYear: j['academic_year'] ?? '',
      semester: j['semester'] ?? '',
      programme: j['programme'] ?? '',
      dryRun: j['dry_run'] ?? false,
      generatedSessions: j['generated_sessions'] ?? 0,
      failedSessions: j['failed_sessions'] ?? 0,
      generated: (details['generated'] as List? ?? [])
          .map((e) => GeneratedEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      failed: (details['failed'] as List? ?? [])
          .map((e) => FailedEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
