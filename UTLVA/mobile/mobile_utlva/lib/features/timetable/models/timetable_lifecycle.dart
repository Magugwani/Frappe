/// Models for Phase 7 — Timetable Lifecycle Management

class TimetableStatusInfo {
  final String dominantStatus; // EMPTY | DRAFT | VALIDATED | PUBLISHED
  final Map<String, int> entryCounts;
  final int openConflicts;
  final int resolvedConflicts;
  final bool canPublish;
  final bool canValidate;
  final String academicYear;
  final String semester;
  final LastPublication? lastPublication;

  const TimetableStatusInfo({
    required this.dominantStatus,
    required this.entryCounts,
    required this.openConflicts,
    required this.resolvedConflicts,
    required this.canPublish,
    required this.canValidate,
    required this.academicYear,
    required this.semester,
    this.lastPublication,
  });

  int get totalEntries => entryCounts['total'] ?? 0;
  int get draftCount => entryCounts['draft'] ?? 0;
  int get validatedCount => entryCounts['validated'] ?? 0;
  int get publishedCount => entryCounts['published'] ?? 0;

  factory TimetableStatusInfo.fromJson(Map<String, dynamic> j) {
    final counts = (j['entry_counts'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    final pub = j['last_publication'] != null
        ? LastPublication.fromJson(j['last_publication'] as Map<String, dynamic>)
        : null;
    return TimetableStatusInfo(
      dominantStatus: j['dominant_status'] ?? 'EMPTY',
      entryCounts: counts,
      openConflicts: j['open_conflicts'] ?? 0,
      resolvedConflicts: j['resolved_conflicts'] ?? 0,
      canPublish: j['can_publish'] ?? false,
      canValidate: j['can_validate'] ?? true,
      academicYear: j['academic_year'] ?? '',
      semester: j['semester'] ?? '',
      lastPublication: pub,
    );
  }
}

class LastPublication {
  final int id;
  final String? publishedBy;
  final String? publishedAt;
  final int entries;

  const LastPublication({required this.id, this.publishedBy, this.publishedAt, required this.entries});

  factory LastPublication.fromJson(Map<String, dynamic> j) => LastPublication(
    id: j['id'] ?? 0,
    publishedBy: j['published_by'],
    publishedAt: j['published_at'],
    entries: j['entries'] ?? 0,
  );
}

class PublishResult {
  final bool success;
  final String status;
  final String message;
  final int? publishedEntries;
  final int? openConflicts;
  final String? publishedAt;

  const PublishResult({
    required this.success,
    required this.status,
    required this.message,
    this.publishedEntries,
    this.openConflicts,
    this.publishedAt,
  });

  factory PublishResult.fromJson(Map<String, dynamic> j) => PublishResult(
    success: j['success'] ?? false,
    status: j['status'] ?? '',
    message: j['message'] ?? '',
    publishedEntries: j['published_entries'],
    openConflicts: j['open_conflicts'],
    publishedAt: j['published_at'],
  );
}

class ConflictItem {
  final int id;
  final String conflictType;
  final String typeDisplay;
  final String message;
  final String status; // OPEN | RESOLVED
  final ConflictEntry entryA;
  final ConflictEntry entryB;
  final String? resolvedBy;
  final String? resolvedAt;
  final String? resolutionNote;
  final String createdAt;

  const ConflictItem({
    required this.id,
    required this.conflictType,
    required this.typeDisplay,
    required this.message,
    required this.status,
    required this.entryA,
    required this.entryB,
    this.resolvedBy,
    this.resolvedAt,
    this.resolutionNote,
    required this.createdAt,
  });

  bool get isOpen => status == 'OPEN';

  factory ConflictItem.fromJson(Map<String, dynamic> j) => ConflictItem(
    id: j['id'],
    conflictType: j['conflict_type'] ?? '',
    typeDisplay: j['type_display'] ?? '',
    message: j['message'] ?? '',
    status: j['status'] ?? 'OPEN',
    entryA: ConflictEntry.fromJson(j['entry_a'] as Map<String, dynamic>? ?? {}),
    entryB: ConflictEntry.fromJson(j['entry_b'] as Map<String, dynamic>? ?? {}),
    resolvedBy: j['resolved_by'],
    resolvedAt: j['resolved_at'],
    resolutionNote: j['resolution_note'],
    createdAt: j['created_at'] ?? '',
  );
}

class ConflictEntry {
  final int id;
  final String course;
  final String day;
  final String time;

  const ConflictEntry({required this.id, required this.course, required this.day, required this.time});

  factory ConflictEntry.fromJson(Map<String, dynamic> j) => ConflictEntry(
    id: j['id'] ?? 0,
    course: j['course'] ?? '',
    day: j['day'] ?? '',
    time: j['time'] ?? '',
  );
}
