/// Minimal student identity record.
/// Links a student user to their academic placement (programme + group).
/// Enables automatic timetable filtering — the student does not have to
/// select their programme/group manually on every screen visit.
class StudentProfile {
  final int id;
  final int userId;
  final String fullName;
  final String email;
  final String registrationNumber;
  final int? programmeId;
  final String? programmeName;
  final String? programmeCode;
  final int? studentGroupId;
  final String? studentGroupName;

  const StudentProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.registrationNumber,
    this.programmeId,
    this.programmeName,
    this.programmeCode,
    this.studentGroupId,
    this.studentGroupName,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> j) => StudentProfile(
        id: j['id'],
        userId: j['user'],
        fullName: j['full_name'] ?? '',
        email: j['email'] ?? '',
        registrationNumber: j['registration_number'] ?? '',
        programmeId: j['programme'],
        programmeName: j['programme_name'],
        programmeCode: j['programme_code'],
        studentGroupId: j['student_group'],
        studentGroupName: j['student_group_name'],
      );

  Map<String, dynamic> toJson() => {
        'user': userId,
        'registration_number': registrationNumber,
        if (programmeId != null) 'programme': programmeId,
        if (studentGroupId != null) 'student_group': studentGroupId,
      };

  bool get isComplete => programmeId != null;
}
