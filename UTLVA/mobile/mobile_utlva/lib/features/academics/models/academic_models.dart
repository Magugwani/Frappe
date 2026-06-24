class AcademicYear {
  final int id;
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final bool isActive;

  const AcademicYear({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.isActive = false,
  });

  factory AcademicYear.fromJson(Map<String, dynamic> j) => AcademicYear(
        id: j['id'],
        name: j['name'],
        startDate: j['start_date'],
        endDate: j['end_date'],
        status: j['status'],
        isActive: j['is_active'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
        'status': status,
      };
}

class Semester {
  final int id;
  final int academicYearId;
  final String academicYearName;
  final String name;
  final String startDate;
  final String endDate;
  final bool isActive;
  final int teachingPeriodCount;

  const Semester({
    required this.id,
    required this.academicYearId,
    required this.academicYearName,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.teachingPeriodCount = 0,
  });

  factory Semester.fromJson(Map<String, dynamic> j) => Semester(
        id: j['id'],
        academicYearId: j['academic_year'],
        academicYearName: j['academic_year_name'] ?? '',
        name: j['name'],
        startDate: j['start_date'],
        endDate: j['end_date'],
        isActive: j['is_active'] ?? true,
        teachingPeriodCount: j['teaching_period_count'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'academic_year': academicYearId,
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
        'is_active': isActive,
      };
}

class Department {
  final int id;
  final String name;
  final String code;

  const Department({required this.id, required this.name, required this.code});

  factory Department.fromJson(Map<String, dynamic> j) =>
      Department(id: j['id'], name: j['name'], code: j['code']);

  Map<String, dynamic> toJson() => {'name': name, 'code': code};
}

class Programme {
  final int id;
  final int departmentId;
  final String departmentName;
  final String departmentCode;
  final String name;
  final String code;
  final int durationYears;

  const Programme({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    required this.departmentCode,
    required this.name,
    required this.code,
    required this.durationYears,
  });

  factory Programme.fromJson(Map<String, dynamic> j) => Programme(
        id: j['id'],
        departmentId: j['department'],
        departmentName: j['department_name'] ?? '',
        departmentCode: j['department_code'] ?? '',
        name: j['name'],
        code: j['code'],
        durationYears: j['duration_years'] ?? 3,
      );

  Map<String, dynamic> toJson() => {
        'department': departmentId,
        'name': name,
        'code': code,
        'duration_years': durationYears,
      };
}

class StudentGroup {
  final int id;
  final int programmeId;
  final String programmeName;
  final String programmeCode;
  final int? academicYearId;
  final String? academicYearName;
  final int yearOfStudy;
  final String groupName;
  final int studentCount;
  final String displayName;

  const StudentGroup({
    required this.id,
    required this.programmeId,
    required this.programmeName,
    required this.programmeCode,
    this.academicYearId,
    this.academicYearName,
    required this.yearOfStudy,
    required this.groupName,
    this.studentCount = 0,
    required this.displayName,
  });

  factory StudentGroup.fromJson(Map<String, dynamic> j) => StudentGroup(
        id: j['id'],
        programmeId: j['programme'],
        programmeName: j['programme_name'] ?? '',
        programmeCode: j['programme_code'] ?? '',
        academicYearId: j['academic_year'],
        academicYearName: j['academic_year_name'],
        yearOfStudy: j['year_of_study'],
        groupName: j['group_name'],
        studentCount: j['student_count'] ?? 0,
        displayName: j['display_name'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'programme': programmeId,
        'year_of_study': yearOfStudy,
        'group_name': groupName,
        'student_count': studentCount,
        if (academicYearId != null) 'academic_year': academicYearId,
      };
}

class Course {
  final int id;
  final String courseCode;
  final String courseName;
  final int programmeId;
  final String programmeName;
  final int? semesterId;
  final String? semesterName;
  final int yearOfStudy;
  final int creditHours;
  final int weeklyHours;
  final String requiredVenueType;
  final List<dynamic> requiredResources;

  const Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.programmeId,
    required this.programmeName,
    this.semesterId,
    this.semesterName,
    required this.yearOfStudy,
    required this.creditHours,
    required this.weeklyHours,
    required this.requiredVenueType,
    required this.requiredResources,
  });

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'],
        courseCode: j['course_code'],
        courseName: j['course_name'],
        programmeId: j['programme'],
        programmeName: j['programme_name'] ?? '',
        semesterId: j['semester'],
        semesterName: j['semester_name'],
        yearOfStudy: j['year_of_study'] ?? 1,
        creditHours: j['credit_hours'] ?? 3,
        weeklyHours: j['weekly_hours'] ?? 3,
        requiredVenueType: j['required_venue_type'] ?? '',
        requiredResources: j['required_resources'] ?? [],
      );

  Map<String, dynamic> toJson() => {
        'course_code': courseCode,
        'course_name': courseName,
        'programme': programmeId,
        if (semesterId != null) 'semester': semesterId,
        'year_of_study': yearOfStudy,
        'credit_hours': creditHours,
        'weekly_hours': weeklyHours,
        'required_venue_type': requiredVenueType,
        'required_resources': requiredResources,
      };
}

class Lecturer {
  final int id;
  final int userId;
  final String fullName;
  final String email;
  final String staffNumber;
  final int? departmentId;
  final String? departmentName;
  final List<dynamic> courseAssignments;

  const Lecturer({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.staffNumber,
    this.departmentId,
    this.departmentName,
    required this.courseAssignments,
  });

  factory Lecturer.fromJson(Map<String, dynamic> j) => Lecturer(
        id: j['id'],
        userId: j['user'],
        fullName: j['full_name'] ?? '',
        email: j['email'] ?? '',
        staffNumber: j['staff_number'],
        departmentId: j['department'],
        departmentName: j['department_name'],
        courseAssignments: j['course_assignments'] ?? [],
      );

  Map<String, dynamic> toJson() => {
        'user': userId,
        'staff_number': staffNumber,
        if (departmentId != null) 'department': departmentId,
      };
}

/// Represents a candidate time slot that the timetable generator uses
/// to place courses. Defined by the coordinator per semester.
///
/// Example: Monday 08:00–10:00 in Semester One 2025/2026.
///
/// Phase 5 will iterate over active TeachingPeriods to auto-assign
/// courses, checking lecturer/student/venue availability for each.
class TeachingPeriod {
  final int id;
  final int semesterId;
  final String semesterName;
  final String academicYearName;
  final String dayOfWeek;
  final String dayDisplay;
  final String startTime; // "08:00:00"
  final String endTime;   // "10:00:00"
  final String label;
  final bool isActive;
  final int durationMinutes;

  const TeachingPeriod({
    required this.id,
    required this.semesterId,
    required this.semesterName,
    required this.academicYearName,
    required this.dayOfWeek,
    required this.dayDisplay,
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.isActive,
    required this.durationMinutes,
  });

  factory TeachingPeriod.fromJson(Map<String, dynamic> j) => TeachingPeriod(
        id: j['id'],
        semesterId: j['semester'],
        semesterName: j['semester_name'] ?? '',
        academicYearName: j['academic_year_name'] ?? '',
        dayOfWeek: j['day_of_week'] ?? '',
        dayDisplay: j['day_display'] ?? '',
        startTime: j['start_time'] ?? '',
        endTime: j['end_time'] ?? '',
        label: j['label'] ?? '',
        isActive: j['is_active'] ?? true,
        durationMinutes: j['duration_minutes'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'semester': semesterId,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'label': label,
        'is_active': isActive,
      };

  String get startHHMM {
    final p = startTime.split(':');
    return '${p[0]}:${p[1]}';
  }

  String get endHHMM {
    final p = endTime.split(':');
    return '${p[0]}:${p[1]}';
  }

  String get displayLabel => label.isNotEmpty ? label : '$dayDisplay $startHHMM–$endHHMM';
}
