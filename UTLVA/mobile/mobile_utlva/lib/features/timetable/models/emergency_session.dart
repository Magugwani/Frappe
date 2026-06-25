class EmergencySession {
  final int id;
  final int courseId;
  final String courseCode;
  final String courseName;
  final int lecturerId;
  final String lecturerName;
  final int? venueId;
  final String? venueCode;
  final String? venueName;
  final List<int> studentGroupIds;
  final String requestedDate;
  final String dayOfWeek;
  final String dayDisplay;
  final String startTime;
  final String endTime;
  final String reason;
  final String status;
  final String statusDisplay;
  final int? requestedBy;
  final String? requestedByName;
  final int? reviewedBy;
  final String? reviewedByName;
  final String? reviewedAt;
  final String reviewNote;
  final bool lecturerConflict;
  final bool venueConflict;
  final bool groupConflict;
  final String createdAt;

  const EmergencySession({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.lecturerId,
    required this.lecturerName,
    this.venueId,
    this.venueCode,
    this.venueName,
    required this.studentGroupIds,
    required this.requestedDate,
    required this.dayOfWeek,
    required this.dayDisplay,
    required this.startTime,
    required this.endTime,
    required this.reason,
    required this.status,
    required this.statusDisplay,
    this.requestedBy,
    this.requestedByName,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewedAt,
    required this.reviewNote,
    required this.lecturerConflict,
    required this.venueConflict,
    required this.groupConflict,
    required this.createdAt,
  });

  bool get hasConflicts => lecturerConflict || venueConflict || groupConflict;

  factory EmergencySession.fromJson(Map<String, dynamic> j) => EmergencySession(
        id: j['id'] as int,
        courseId: j['course'] as int,
        courseCode: j['course_code'] as String? ?? '',
        courseName: j['course_name'] as String? ?? '',
        lecturerId: j['lecturer'] as int,
        lecturerName: j['lecturer_name'] as String? ?? '',
        venueId: j['venue'] as int?,
        venueCode: j['venue_code'] as String?,
        venueName: j['venue_name'] as String?,
        studentGroupIds: (j['student_group_ids'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        requestedDate: j['requested_date'] as String? ?? '',
        dayOfWeek: j['day_of_week'] as String? ?? '',
        dayDisplay: j['day_display'] as String? ?? '',
        startTime: j['start_time'] as String? ?? '',
        endTime: j['end_time'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        status: j['status'] as String? ?? 'PENDING',
        statusDisplay: j['status_display'] as String? ?? 'Pending Review',
        requestedBy: j['requested_by'] as int?,
        requestedByName: j['requested_by_name'] as String?,
        reviewedBy: j['reviewed_by'] as int?,
        reviewedByName: j['reviewed_by_name'] as String?,
        reviewedAt: j['reviewed_at'] as String?,
        reviewNote: j['review_note'] as String? ?? '',
        lecturerConflict: j['lecturer_conflict'] as bool? ?? false,
        venueConflict: j['venue_conflict'] as bool? ?? false,
        groupConflict: j['group_conflict'] as bool? ?? false,
        createdAt: j['created_at'] as String? ?? '',
      );
}
