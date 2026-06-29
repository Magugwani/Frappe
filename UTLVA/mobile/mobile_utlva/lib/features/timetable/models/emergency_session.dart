class EmergencySession {
  final int id;
  // FR-23 required session fields
  final String title;
  final int courseId;
  final String courseCode;
  final String courseName;
  final int lecturerId;
  final String lecturerName;
  final int? expectedStudents;
  final List<dynamic> requiredResources;
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
  final String comments;
  final String status;
  final String statusDisplay;
  final int? requestedBy;
  final String? requestedByName;
  final int? reviewedBy;
  final String? reviewedByName;
  final String? reviewedAt;
  final String reviewNote;
  // FR-24 conflict flags
  final bool lecturerConflict;
  final bool venueConflict;
  final bool groupConflict;
  final bool capacityConflict;
  final String createdAt;

  const EmergencySession({
    required this.id,
    this.title = '',
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.lecturerId,
    required this.lecturerName,
    this.expectedStudents,
    this.requiredResources = const [],
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
    this.comments = '',
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
    this.capacityConflict = false,
    required this.createdAt,
  });

  bool get hasConflicts =>
      lecturerConflict || venueConflict || groupConflict || capacityConflict;

  factory EmergencySession.fromJson(Map<String, dynamic> j) => EmergencySession(
        id: j['id'] as int,
        title: j['title'] as String? ?? '',
        courseId: j['course'] as int,
        courseCode: j['course_code'] as String? ?? '',
        courseName: j['course_name'] as String? ?? '',
        lecturerId: j['lecturer'] as int,
        lecturerName: j['lecturer_name'] as String? ?? '',
        expectedStudents: j['expected_students'] as int?,
        requiredResources: j['required_resources'] as List<dynamic>? ?? [],
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
        comments: j['comments'] as String? ?? '',
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
        capacityConflict: j['capacity_conflict'] as bool? ?? false,
        createdAt: j['created_at'] as String? ?? '',
      );
}

/// Model for a single session postponement (FR-26, FR-27).
class SessionPostponement {
  final int id;
  final int originalEntryId;
  final String originalCourseCode;
  final String newDate;
  final String newDayOfWeek;
  final String newDayDisplay;
  final String newStartTime;
  final String newEndTime;
  final int? newVenueId;
  final String? newVenueCode;
  final String reason;
  final String? postponedByName;
  final String postponedAt;

  const SessionPostponement({
    required this.id,
    required this.originalEntryId,
    required this.originalCourseCode,
    required this.newDate,
    required this.newDayOfWeek,
    required this.newDayDisplay,
    required this.newStartTime,
    required this.newEndTime,
    this.newVenueId,
    this.newVenueCode,
    required this.reason,
    this.postponedByName,
    required this.postponedAt,
  });

  factory SessionPostponement.fromJson(Map<String, dynamic> j) =>
      SessionPostponement(
        id: j['id'],
        originalEntryId: j['original_entry'] ?? 0,
        originalCourseCode: j['original_course_code'] ?? '',
        newDate: j['new_date'] ?? '',
        newDayOfWeek: j['new_day_of_week'] ?? '',
        newDayDisplay: j['new_day_display'] ?? '',
        newStartTime: j['new_start_time'] ?? '',
        newEndTime: j['new_end_time'] ?? '',
        newVenueId: j['new_venue'] as int?,
        newVenueCode: j['new_venue_code'] as String?,
        reason: j['reason'] ?? '',
        postponedByName: j['postponed_by_name'] as String?,
        postponedAt: j['postponed_at'] ?? '',
      );
}

/// Assigned course for a lecturer (FR-20).
class LecturerCourse {
  final int assignmentId;
  final int courseId;
  final String courseCode;
  final String courseName;
  final String programmeCode;
  final String programmeName;
  final int yearOfStudy;
  final int weeklyHours;
  final int creditHours;
  final String requiredVenueType;
  final String? academicYear;

  const LecturerCourse({
    required this.assignmentId,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.programmeCode,
    required this.programmeName,
    required this.yearOfStudy,
    required this.weeklyHours,
    required this.creditHours,
    required this.requiredVenueType,
    this.academicYear,
  });

  factory LecturerCourse.fromJson(Map<String, dynamic> j) => LecturerCourse(
        assignmentId: j['assignment_id'] ?? 0,
        courseId: j['course_id'] ?? 0,
        courseCode: j['course_code'] ?? '',
        courseName: j['course_name'] ?? '',
        programmeCode: j['programme_code'] ?? '',
        programmeName: j['programme_name'] ?? '',
        yearOfStudy: j['year_of_study'] ?? 1,
        weeklyHours: j['weekly_hours'] ?? 0,
        creditHours: j['credit_hours'] ?? 0,
        requiredVenueType: j['required_venue_type'] ?? '',
        academicYear: j['academic_year'] as String?,
      );
}
