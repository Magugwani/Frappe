"""
UTLVA Timetable Validation Engine — Phase 6

Responsibility
--------------
Detect scheduling conflicts in a semester's timetable entries.

Three conflict types are checked:
  1. VENUE_CONFLICT      — same venue, overlapping time on the same day
  2. LECTURER_CONFLICT   — same lecturer, overlapping time on the same day
  3. STUDENT_GROUP_CONFLICT — same student group, overlapping time on the same day

Time overlap rule (from SRS):
  A_start < B_end  AND  A_end > B_start

Example that is correctly detected as conflict:
  Entry A: Monday 08:00–10:00
  Entry B: Monday 09:00–11:00
  08:00 < 11:00 → True   AND   10:00 > 09:00 → True  → CONFLICT

Example correctly allowed:
  Entry A: Monday 08:00–10:00
  Entry B: Monday 10:00–12:00
  08:00 < 12:00 → True   AND   10:00 > 10:00 → False → NO CONFLICT

Validation workflow
-------------------
1. Delete all existing OPEN conflicts for this semester.
2. Load all DRAFT/VALIDATED/PUBLISHED entries.
3. Group entries by day_of_week for efficient pairing.
4. Compare every pair of entries that share the same day.
5. For each overlapping pair, check venue/lecturer/group identity.
6. Write a TimetableConflict record for each violation found.
7. If zero conflicts: promote DRAFT entries → VALIDATED.
8. Return a structured ValidationResult.

Note: This is a foundational conflict engine.  An advanced conflict resolution
workflow (bulk fix, clash explorer, etc.) comes in a later phase.
"""

from dataclasses import dataclass, field
from itertools import combinations
from typing import List

from timetable.models import TimetableEntry, TimetableConflict


# ── Result data classes ───────────────────────────────────────────────────────

@dataclass
class ConflictDetail:
    conflict_id: int
    conflict_type: str
    type_display: str
    message: str
    entry_a_id: int
    entry_a_course: str
    entry_a_day: str
    entry_a_time: str
    entry_b_id: int
    entry_b_course: str
    entry_b_day: str
    entry_b_time: str

    def to_dict(self) -> dict:
        return {
            'id': self.conflict_id,
            'type': self.conflict_type,
            'type_display': self.type_display,
            'message': self.message,
            'entry_a': {
                'id': self.entry_a_id,
                'course': self.entry_a_course,
                'day': self.entry_a_day,
                'time': self.entry_a_time,
            },
            'entry_b': {
                'id': self.entry_b_id,
                'course': self.entry_b_course,
                'day': self.entry_b_day,
                'time': self.entry_b_time,
            },
        }


@dataclass
class ValidationResult:
    academic_year_name: str
    semester_name: str
    total_entries: int
    conflicts: List[ConflictDetail] = field(default_factory=list)
    validated_count: int = 0

    @property
    def status(self) -> str:
        return 'PASSED' if not self.conflicts else 'FAILED'

    @property
    def total_conflicts(self) -> int:
        return len(self.conflicts)

    @property
    def venue_conflicts(self) -> int:
        return sum(1 for c in self.conflicts if c.conflict_type == 'VENUE_CONFLICT')

    @property
    def lecturer_conflicts(self) -> int:
        return sum(1 for c in self.conflicts if c.conflict_type == 'LECTURER_CONFLICT')

    @property
    def group_conflicts(self) -> int:
        return sum(1 for c in self.conflicts if c.conflict_type == 'STUDENT_GROUP_CONFLICT')

    def to_dict(self) -> dict:
        return {
            'status': self.status,
            'academic_year': self.academic_year_name,
            'semester': self.semester_name,
            'total_entries_checked': self.total_entries,
            'total_conflicts': self.total_conflicts,
            'venue_conflicts': self.venue_conflicts,
            'lecturer_conflicts': self.lecturer_conflicts,
            'student_group_conflicts': self.group_conflicts,
            'validated_entries': self.validated_count,
            'conflicts': [c.to_dict() for c in self.conflicts],
        }


# ── Validator ─────────────────────────────────────────────────────────────────

class TimetableValidationService:
    """
    Validates all timetable entries for a given semester.

    Parameters
    ----------
    academic_year   AcademicYear instance
    semester        Semester instance
    """

    def __init__(self, academic_year, semester):
        self.year = academic_year
        self.semester = semester

    # ── Public ────────────────────────────────────────────────────────────────

    def validate(self) -> ValidationResult:
        """
        Run full conflict detection for the semester.

        Steps:
          1. Clear previous OPEN conflicts (re-run is idempotent).
          2. Load entries.
          3. Detect all three conflict types.
          4. Persist TimetableConflict records.
          5. Auto-promote DRAFT → VALIDATED if zero conflicts.
          6. Return ValidationResult.
        """
        # Step 1: clear stale OPEN conflicts for this semester
        TimetableConflict.objects.filter(
            timetable_entry_a__semester=self.semester,
            status=TimetableConflict.Status.OPEN,
        ).delete()

        # Step 2: load entries
        entries = list(
            TimetableEntry.objects.filter(
                semester=self.semester,
                status__in=[
                    TimetableStatus.DRAFT,
                    TimetableStatus.VALIDATED,
                    TimetableStatus.PUBLISHED,
                ],
            ).select_related(
                'course', 'venue', 'lecturer__user', 'student_group',
            )
        )

        result = ValidationResult(
            academic_year_name=self.year.name,
            semester_name=self.semester.name,
            total_entries=len(entries),
        )

        if len(entries) < 2:
            # Nothing to compare
            if entries:
                self._promote_to_validated(entries)
                result.validated_count = len(entries)
            return result

        # Step 3 + 4: detect conflicts and persist
        conflict_objects = []
        seen_pairs: set = set()

        # Group by day to reduce comparisons from O(n²) to O(k²) per day
        from collections import defaultdict
        by_day: dict = defaultdict(list)
        for e in entries:
            by_day[e.day_of_week].append(e)

        for day_entries in by_day.values():
            for a, b in combinations(day_entries, 2):
                if not self._overlaps(a, b):
                    continue

                # Venue conflict
                if a.venue_id and b.venue_id and a.venue_id == b.venue_id:
                    pair_key = ('VENUE', min(a.id, b.id), max(a.id, b.id))
                    if pair_key not in seen_pairs:
                        seen_pairs.add(pair_key)
                        conflict_objects.append(TimetableConflict(
                            conflict_type=TimetableConflict.ConflictType.VENUE,
                            timetable_entry_a=a,
                            timetable_entry_b=b,
                            message=(
                                f'{a.venue.name} is double-booked on {a.day_of_week} '
                                f'{a.start_time.strftime("%H:%M")}–{b.end_time.strftime("%H:%M")}: '
                                f'{a.course.course_code} and {b.course.course_code}'
                            ),
                        ))

                # Lecturer conflict
                if a.lecturer_id and b.lecturer_id and a.lecturer_id == b.lecturer_id:
                    pair_key = ('LECTURER', min(a.id, b.id), max(a.id, b.id))
                    if pair_key not in seen_pairs:
                        seen_pairs.add(pair_key)
                        conflict_objects.append(TimetableConflict(
                            conflict_type=TimetableConflict.ConflictType.LECTURER,
                            timetable_entry_a=a,
                            timetable_entry_b=b,
                            message=(
                                f'{a.lecturer.user.full_name} is assigned to two overlapping sessions '
                                f'on {a.day_of_week}: '
                                f'{a.course.course_code} ({a.start_time.strftime("%H:%M")}–{a.end_time.strftime("%H:%M")}) '
                                f'and {b.course.course_code} ({b.start_time.strftime("%H:%M")}–{b.end_time.strftime("%H:%M")})'
                            ),
                        ))

                # Student group conflict
                if (a.student_group_id and b.student_group_id
                        and a.student_group_id == b.student_group_id):
                    pair_key = ('GROUP', min(a.id, b.id), max(a.id, b.id))
                    if pair_key not in seen_pairs:
                        seen_pairs.add(pair_key)
                        conflict_objects.append(TimetableConflict(
                            conflict_type=TimetableConflict.ConflictType.STUDENT_GROUP,
                            timetable_entry_a=a,
                            timetable_entry_b=b,
                            message=(
                                f'{a.student_group} has two overlapping sessions '
                                f'on {a.day_of_week}: '
                                f'{a.course.course_code} ({a.start_time.strftime("%H:%M")}–{a.end_time.strftime("%H:%M")}) '
                                f'and {b.course.course_code} ({b.start_time.strftime("%H:%M")}–{b.end_time.strftime("%H:%M")})'
                            ),
                        ))

        # Bulk insert conflicts
        created = TimetableConflict.objects.bulk_create(conflict_objects)

        # Populate result
        for obj in created:
            a = obj.timetable_entry_a
            b = obj.timetable_entry_b
            result.conflicts.append(ConflictDetail(
                conflict_id=obj.pk,
                conflict_type=obj.conflict_type,
                type_display=obj.get_conflict_type_display(),
                message=obj.message,
                entry_a_id=a.id,
                entry_a_course=a.course.course_code,
                entry_a_day=a.day_of_week,
                entry_a_time=f'{a.start_time.strftime("%H:%M")}–{a.end_time.strftime("%H:%M")}',
                entry_b_id=b.id,
                entry_b_course=b.course.course_code,
                entry_b_day=b.day_of_week,
                entry_b_time=f'{b.start_time.strftime("%H:%M")}–{b.end_time.strftime("%H:%M")}',
            ))

        # Step 5: promote DRAFT → VALIDATED if clean
        if not result.conflicts:
            self._promote_to_validated(entries)
            result.validated_count = len([e for e in entries
                                          if e.status in (TimetableStatus.DRAFT, TimetableStatus.VALIDATED)])

        return result

    # ── Private ───────────────────────────────────────────────────────────────

    @staticmethod
    def _overlaps(a: TimetableEntry, b: TimetableEntry) -> bool:
        """
        Returns True if entry A and entry B have a time overlap ON THE SAME DAY.

        Overlap rule (SRS):  A_start < B_end  AND  A_end > B_start

        Boundary adjacency (08:00–10:00 and 10:00–12:00) is NOT an overlap
        because 10:00 > 10:00 is False.
        """
        if a.day_of_week != b.day_of_week:
            return False
        return a.start_time < b.end_time and a.end_time > b.start_time

    @staticmethod
    def _promote_to_validated(entries: list) -> None:
        """Bulk-promote DRAFT entries to VALIDATED."""
        ids = [e.id for e in entries if e.status == TimetableStatus.DRAFT]
        if ids:
            TimetableEntry.objects.filter(pk__in=ids).update(
                status=TimetableStatus.VALIDATED
            )


# Make TimetableStatus importable from this module
from timetable.models import TimetableStatus  # noqa: E402 (must be after model import)
