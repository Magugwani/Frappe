class ConflictEntry {
  final int id;
  final String course;
  final String day;
  final String time;

  const ConflictEntry({
    required this.id,
    required this.course,
    required this.day,
    required this.time,
  });

  factory ConflictEntry.fromJson(Map<String, dynamic> j) => ConflictEntry(
        id: j['id'] ?? 0,
        course: j['course'] ?? '',
        day: j['day'] ?? '',
        time: j['time'] ?? '',
      );
}

class TimetableConflict {
  final int id;
  final String conflictType;   // VENUE_CONFLICT | LECTURER_CONFLICT | STUDENT_GROUP_CONFLICT
  final String typeDisplay;
  final String message;
  final ConflictEntry entryA;
  final ConflictEntry entryB;

  const TimetableConflict({
    required this.id,
    required this.conflictType,
    required this.typeDisplay,
    required this.message,
    required this.entryA,
    required this.entryB,
  });

  factory TimetableConflict.fromJson(Map<String, dynamic> j) => TimetableConflict(
        id: j['id'] ?? 0,
        conflictType: j['type'] ?? '',
        typeDisplay: j['type_display'] ?? '',
        message: j['message'] ?? '',
        entryA: ConflictEntry.fromJson(j['entry_a'] as Map<String, dynamic>? ?? {}),
        entryB: ConflictEntry.fromJson(j['entry_b'] as Map<String, dynamic>? ?? {}),
      );

  bool get isVenueConflict => conflictType == 'VENUE_CONFLICT';
  bool get isLecturerConflict => conflictType == 'LECTURER_CONFLICT';
  bool get isGroupConflict => conflictType == 'STUDENT_GROUP_CONFLICT';
}

class ValidationResult {
  final String status;        // PASSED | FAILED
  final String academicYear;
  final String semester;
  final int totalEntriesChecked;
  final int totalConflicts;
  final int venueConflicts;
  final int lecturerConflicts;
  final int studentGroupConflicts;
  final int validatedEntries;
  final List<TimetableConflict> conflicts;

  const ValidationResult({
    required this.status,
    required this.academicYear,
    required this.semester,
    required this.totalEntriesChecked,
    required this.totalConflicts,
    required this.venueConflicts,
    required this.lecturerConflicts,
    required this.studentGroupConflicts,
    required this.validatedEntries,
    required this.conflicts,
  });

  bool get isPassed => status == 'PASSED';

  factory ValidationResult.fromJson(Map<String, dynamic> j) => ValidationResult(
        status: j['status'] ?? 'FAILED',
        academicYear: j['academic_year'] ?? '',
        semester: j['semester'] ?? '',
        totalEntriesChecked: j['total_entries_checked'] ?? 0,
        totalConflicts: j['total_conflicts'] ?? 0,
        venueConflicts: j['venue_conflicts'] ?? 0,
        lecturerConflicts: j['lecturer_conflicts'] ?? 0,
        studentGroupConflicts: j['student_group_conflicts'] ?? 0,
        validatedEntries: j['validated_entries'] ?? 0,
        conflicts: (j['conflicts'] as List? ?? [])
            .map((c) => TimetableConflict.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
