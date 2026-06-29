class TimetableEntry {
  final int id;
  final int academicYearId;
  final String academicYearName;
  final int semesterId;
  final String semesterName;
  final int programmeId;
  final String programmeName;
  final String programmeCode;
  final int? studentGroupId;
  final String? studentGroupName;
  final int courseId;
  final String courseCode;
  final String courseName;
  final int lecturerId;
  final String lecturerName;
  final int? venueId;
  final String? venueCode;
  final String? venueName;
  // Live timetable: venue status + location for map navigation
  final String? venueStatus;          // FREE | BOOKED | IN_USE | EXPIRED | MAINTENANCE
  final String? venueStatusDisplay;
  final String? venueMarkerColor;     // hex color matching status
  final double? venueLatitude;
  final double? venueLongitude;
  final int? venueFloor;
  final String? venueBuildingName;
  final String? venueIndoorIdentifier;

  final String dayOfWeek;
  final String? date;
  final String startTime; // "08:00:00"
  final String endTime;   // "10:00:00"
  final String status;

  const TimetableEntry({
    required this.id,
    required this.academicYearId,
    required this.academicYearName,
    required this.semesterId,
    required this.semesterName,
    required this.programmeId,
    required this.programmeName,
    required this.programmeCode,
    this.studentGroupId,
    this.studentGroupName,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.lecturerId,
    required this.lecturerName,
    this.venueId,
    this.venueCode,
    this.venueName,
    this.venueStatus,
    this.venueStatusDisplay,
    this.venueMarkerColor,
    this.venueLatitude,
    this.venueLongitude,
    this.venueFloor,
    this.venueBuildingName,
    this.venueIndoorIdentifier,
    required this.dayOfWeek,
    this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> j) => TimetableEntry(
        id: j['id'],
        academicYearId: j['academic_year'],
        academicYearName: j['academic_year_name'] ?? '',
        semesterId: j['semester'],
        semesterName: j['semester_name'] ?? '',
        programmeId: j['programme'],
        programmeName: j['programme_name'] ?? '',
        programmeCode: j['programme_code'] ?? '',
        studentGroupId: j['student_group'],
        studentGroupName: j['student_group_name'],
        courseId: j['course'],
        courseCode: j['course_code'] ?? '',
        courseName: j['course_name'] ?? '',
        lecturerId: j['lecturer'],
        lecturerName: j['lecturer_name'] ?? '',
        venueId: j['venue'],
        venueCode: j['venue_code'],
        venueName: j['venue_name'],
        venueStatus: j['venue_status'],
        venueStatusDisplay: j['venue_status_display'],
        venueMarkerColor: j['venue_marker_color'],
        venueLatitude: (j['venue_latitude'] as num?)?.toDouble(),
        venueLongitude: (j['venue_longitude'] as num?)?.toDouble(),
        venueFloor: j['venue_floor'],
        venueBuildingName: j['venue_building_name'],
        venueIndoorIdentifier: j['venue_indoor_identifier'],
        dayOfWeek: j['day_of_week'] ?? '',
        date: j['date'],
        startTime: j['start_time'] ?? '',
        endTime: j['end_time'] ?? '',
        status: j['status'] ?? 'DRAFT',
      );

  Map<String, dynamic> toJson() => {
        'academic_year': academicYearId,
        'semester': semesterId,
        'programme': programmeId,
        if (studentGroupId != null) 'student_group': studentGroupId,
        'course': courseId,
        'lecturer': lecturerId,
        if (venueId != null) 'venue': venueId,
        'day_of_week': dayOfWeek,
        if (date != null) 'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'status': status,
      };

  bool get hasVenueCoordinates =>
      venueLatitude != null && venueLongitude != null;

  /// Start time as minutes for grid positioning.
  int get startMinutes {
    final parts = startTime.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get endMinutes {
    final parts = endTime.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get durationMinutes => endMinutes - startMinutes;

  String get startHHMM {
    final parts = startTime.split(':');
    return '${parts[0]}:${parts[1]}';
  }

  String get endHHMM {
    final parts = endTime.split(':');
    return '${parts[0]}:${parts[1]}';
  }
}
