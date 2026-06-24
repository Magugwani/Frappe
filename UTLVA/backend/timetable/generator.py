"""
UTLVA Timetable Generation Engine — Phase 5

Algorithm
---------
1. Load all required academic data into memory (one DB query per resource).

2. Build a scheduling task list.
   Each task = one session of a course for one student group.
   A course with 4 weekly_hours and 2-hour periods → 2 tasks per group.
   This design allows generating multiple sessions for the same course without
   ever hardcoding "one course = one entry".

3. For each task, iterate through active TeachingPeriods in order and find
   the first (period, venue) pair that satisfies ALL constraints:

     Constraint 1 — Lecturer availability
       The assigned lecturer must not have any booking that overlaps
       with (day, start_time, end_time).

     Constraint 2 — Student group availability
       The student group must have no overlapping booking.

     Constraint 3 — Venue capacity
       venue.capacity >= group.student_count

     Constraint 4 — Venue type (if course specifies one)
       venue.venue_type == course.required_venue_type

     Constraint 5 — Venue resources (if course specifies any)
       All entries in course.required_resources must be in venue.resources

     Constraint 6 — Venue availability
       The venue must have no overlapping booking.

   Overlap rule (as specified in SRS):
       A_start < B_end  AND  A_end > B_start

   This rule is applied to ALL three resource types (lecturer, group, venue)
   so that partial-hour overlaps are always detected.  Example:
       Existing booking : Monday 08:00–10:00
       Candidate slot   : Monday 09:00–11:00
       08:00 < 11:00 → True   AND   10:00 > 09:00 → True  →  OVERLAP DETECTED

4. On success: write a DRAFT TimetableEntry to the database (unless dry_run)
   and immediately add the booking to the in-memory maps so subsequent tasks
   see the correct availability.

5. On failure: record the reason and continue.

Architecture notes
------------------
- All conflict logic lives here; views and serializers contain no scheduling code.
- `GenerationResult` is a pure data object — future optimisation passes can
  inspect and reorder `generated` before returning to the client.
- Variable period durations are fully supported: `sessions_needed` uses the
  actual duration of the period objects, not a hardcoded constant.
"""

import math
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import time as dtime
from typing import Optional, List, Tuple

from academics.models import (
    AcademicYear, Semester, Course, StudentGroup, LecturerCourse, TeachingPeriod,
)
from venues.models import Venue
from timetable.models import TimetableEntry


# ── Booking type alias ────────────────────────────────────────────────────────
# Each booking is (day_of_week: str, start: time, end: time).
# Using time objects allows direct comparison without string parsing.
Booking = Tuple[str, dtime, dtime]


# ── Result data classes ───────────────────────────────────────────────────────

@dataclass
class SchedulingTask:
    """One scheduling unit: a single weekly session of a course for one group."""
    course: object
    lecturer: object
    group: object
    sessions_needed: int   # total sessions per week for this course-group
    session_index: int     # 1-based index (e.g. 1 of 2 for a 4h/week course)

    @property
    def label(self) -> str:
        return (
            f'{self.course.course_code} / {self.group} '
            f'[session {self.session_index}/{self.sessions_needed}]'
        )


@dataclass
class GeneratedEntry:
    course_code: str
    course_name: str
    group_name: str
    lecturer_name: str
    venue_code: str
    venue_name: str
    day_of_week: str
    start_time: str
    end_time: str
    session_index: int
    sessions_needed: int
    entry_id: Optional[int] = None  # set after DB write


@dataclass
class FailedEntry:
    course_code: str
    course_name: str
    group_name: str
    session_index: int
    sessions_needed: int
    reason: str


@dataclass
class GenerationResult:
    academic_year_name: str
    semester_name: str
    programme_name: str
    dry_run: bool
    generated: list = field(default_factory=list)
    failed: list = field(default_factory=list)

    @property
    def generated_count(self) -> int:
        return len(self.generated)

    @property
    def failed_count(self) -> int:
        return len(self.failed)

    def to_dict(self) -> dict:
        return {
            'academic_year': self.academic_year_name,
            'semester': self.semester_name,
            'programme': self.programme_name,
            'dry_run': self.dry_run,
            'generated_sessions': self.generated_count,
            'failed_sessions': self.failed_count,
            'details': {
                'generated': [
                    {
                        'course_code': e.course_code,
                        'course_name': e.course_name,
                        'group': e.group_name,
                        'lecturer': e.lecturer_name,
                        'venue': f'{e.venue_code} — {e.venue_name}',
                        'day': e.day_of_week,
                        'time': f'{e.start_time[:5]}–{e.end_time[:5]}',
                        'session': f'{e.session_index}/{e.sessions_needed}',
                        'entry_id': e.entry_id,
                    }
                    for e in self.generated
                ],
                'failed': [
                    {
                        'course_code': e.course_code,
                        'course_name': e.course_name,
                        'group': e.group_name,
                        'session': f'{e.session_index}/{e.sessions_needed}',
                        'reason': e.reason,
                    }
                    for e in self.failed
                ],
            },
        }


# ── Generator ─────────────────────────────────────────────────────────────────

class TimetableGenerator:
    """
    Automatic timetable generator.

    Parameters
    ----------
    academic_year  AcademicYear instance
    semester       Semester instance (must belong to academic_year)
    programme      Optional Programme instance — restrict to one programme.
                   If None, all programmes that have courses in the semester
                   are processed.
    dry_run        When True, schedule is computed but nothing is written to DB.
    created_by     User instance for TimetableEntry.created_by audit field.
    """

    def __init__(
        self,
        academic_year: AcademicYear,
        semester: Semester,
        programme=None,
        dry_run: bool = False,
        created_by=None,
    ):
        self.year = academic_year
        self.semester = semester
        self.programme = programme
        self.dry_run = dry_run
        self.created_by = created_by

        # Availability maps: resource_id → list of Booking tuples
        # Using lists (not sets) because Booking contains time objects.
        # O(n) per look-up is acceptable given the small number of periods.
        self._lecturer_bookings: dict = defaultdict(list)
        self._group_bookings: dict = defaultdict(list)
        self._venue_bookings: dict = defaultdict(list)

        # Reference data — loaded once
        self._periods: List = list(
            TeachingPeriod.objects.filter(semester=semester, is_active=True)
            .order_by('day_of_week', 'start_time')
        )
        self._venues: List = list(
            Venue.objects.filter(is_active=True)
            .order_by('capacity')  # ascending → prefer smallest sufficient venue
        )

        # Pre-populate bookings from existing DRAFT/PUBLISHED entries
        # so the generator respects manually created timetable entries.
        self._load_existing_bookings()

    # ── Public ────────────────────────────────────────────────────────────────

    def generate(self) -> GenerationResult:
        result = GenerationResult(
            academic_year_name=self.year.name,
            semester_name=self.semester.name,
            programme_name=self.programme.name if self.programme else 'All programmes',
            dry_run=self.dry_run,
        )

        tasks = self._build_task_list(result)

        for task in tasks:
            placement = self._schedule_task(task)
            if placement is None:
                result.failed.append(FailedEntry(
                    course_code=task.course.course_code,
                    course_name=task.course.course_name,
                    group_name=str(task.group),
                    session_index=task.session_index,
                    sessions_needed=task.sessions_needed,
                    reason=self._diagnose_failure(task),
                ))
            else:
                period = placement['period']
                venue = placement['venue']

                # Write to DB (unless preview / dry run)
                entry_id = None
                if not self.dry_run:
                    db_obj = TimetableEntry.objects.create(
                        academic_year=self.year,
                        semester=self.semester,
                        programme=task.course.programme,
                        student_group=task.group,
                        course=task.course,
                        lecturer=task.lecturer,
                        venue=venue,
                        day_of_week=period.day_of_week,
                        start_time=period.start_time,
                        end_time=period.end_time,
                        status='DRAFT',
                        created_by=self.created_by,
                    )
                    entry_id = db_obj.pk

                # Mark resources consumed so subsequent tasks see correct state
                booking: Booking = (period.day_of_week, period.start_time, period.end_time)
                self._lecturer_bookings[task.lecturer.id].append(booking)
                self._group_bookings[task.group.id].append(booking)
                self._venue_bookings[venue.id].append(booking)

                result.generated.append(GeneratedEntry(
                    course_code=task.course.course_code,
                    course_name=task.course.course_name,
                    group_name=str(task.group),
                    lecturer_name=task.lecturer.user.full_name,
                    venue_code=venue.code,
                    venue_name=venue.name,
                    day_of_week=period.day_of_week,
                    start_time=str(period.start_time),
                    end_time=str(period.end_time),
                    session_index=task.session_index,
                    sessions_needed=task.sessions_needed,
                    entry_id=entry_id,
                ))

        return result

    # ── Conflict detection ────────────────────────────────────────────────────

    @staticmethod
    def _overlaps(new_day: str, new_start: dtime, new_end: dtime,
                  bookings: List[Booking]) -> bool:
        """
        Returns True if (new_day, new_start, new_end) overlaps with any booking.

        Overlap rule (from SRS):
            A_start < B_end  AND  A_end > B_start

        Example that would be MISSED by an exact-match check but caught here:
            Existing: Monday 08:00–10:00
            Candidate: Monday 09:00–11:00
            09:00 < 10:00  →  True
            11:00 > 08:00  →  True
            Result: OVERLAP (correctly detected)
        """
        for (b_day, b_start, b_end) in bookings:
            if b_day != new_day:
                continue
            if new_start < b_end and new_end > b_start:
                return True
        return False

    def _load_existing_bookings(self):
        """
        Pre-populate conflict maps from all DRAFT/PUBLISHED entries in this
        semester so the generator never double-books resources that were
        manually entered before generation was triggered.
        """
        qs = TimetableEntry.objects.filter(
            semester=self.semester,
            status__in=['DRAFT', 'PUBLISHED'],
        ).values(
            'lecturer_id', 'student_group_id', 'venue_id',
            'day_of_week', 'start_time', 'end_time',
        )
        for row in qs:
            booking: Booking = (row['day_of_week'], row['start_time'], row['end_time'])
            if row['lecturer_id']:
                self._lecturer_bookings[row['lecturer_id']].append(booking)
            if row['student_group_id']:
                self._group_bookings[row['student_group_id']].append(booking)
            if row['venue_id']:
                self._venue_bookings[row['venue_id']].append(booking)

    # ── Task building ─────────────────────────────────────────────────────────

    def _build_task_list(self, result: GenerationResult) -> List[SchedulingTask]:
        """
        Convert courses into SchedulingTask objects.

        Multi-session support:
        ----------------------
        sessions_needed is derived from the course's weekly_hours and the
        average duration of the teaching periods defined for this semester.
        Example:
            course.weekly_hours = 4
            average period duration = 2 hours
            sessions_needed = ceil(4 / 2) = 2
            → Task(session 1/2) and Task(session 2/2) are created separately.

        Courses that immediately fail (no lecturer, no groups) are added to
        result.failed here so they appear in the report even if no task is built.
        """
        tasks: List[SchedulingTask] = []

        # Average period duration in hours (used for sessions_needed)
        if self._periods:
            avg_period_hours = sum(
                (p.end_time.hour * 60 + p.end_time.minute
                 - p.start_time.hour * 60 - p.start_time.minute) / 60
                for p in self._periods
            ) / len(self._periods)
            avg_period_hours = max(avg_period_hours, 1)  # safety floor
        else:
            avg_period_hours = 2.0

        # Filter courses to this semester (and optionally one programme)
        course_qs = (
            Course.objects
            .filter(semester=self.semester)
            .select_related('programme')
        )
        if self.programme:
            course_qs = course_qs.filter(programme=self.programme)

        # Bulk-fetch lecturer assignments to avoid N+1 queries
        assignments = {
            lc.course_id: lc.lecturer
            for lc in LecturerCourse.objects.filter(
                academic_year=self.year,
                course__in=course_qs,
            ).select_related('lecturer__user')
        }

        for course in course_qs:
            lecturer = assignments.get(course.id)

            if not lecturer:
                result.failed.append(FailedEntry(
                    course_code=course.course_code,
                    course_name=course.course_name,
                    group_name='—',
                    session_index=1,
                    sessions_needed=1,
                    reason='No lecturer assigned for this academic year.',
                ))
                continue

            # Student groups for this course: same programme + year_of_study
            groups_qs = StudentGroup.objects.filter(
                programme=course.programme,
                year_of_study=course.year_of_study,
                academic_year=self.year,
            )
            if self.programme:
                groups_qs = groups_qs.filter(programme=self.programme)

            if not groups_qs.exists():
                result.failed.append(FailedEntry(
                    course_code=course.course_code,
                    course_name=course.course_name,
                    group_name='—',
                    session_index=1,
                    sessions_needed=1,
                    reason=(
                        f'No student groups found for {course.programme.code} '
                        f'Year {course.year_of_study} in academic year {self.year.name}.'
                    ),
                ))
                continue

            # How many sessions does this course need per week?
            sessions_needed = max(1, math.ceil(
                (course.weekly_hours or avg_period_hours) / avg_period_hours
            ))

            for group in groups_qs:
                for i in range(sessions_needed):
                    tasks.append(SchedulingTask(
                        course=course,
                        lecturer=lecturer,
                        group=group,
                        sessions_needed=sessions_needed,
                        session_index=i + 1,
                    ))

        return tasks

    # ── Slot finding ──────────────────────────────────────────────────────────

    def _schedule_task(self, task: SchedulingTask) -> Optional[dict]:
        """
        Find the first period + venue that satisfies all six constraints.
        Returns {'period': ..., 'venue': ...} or None.
        """
        for period in self._periods:
            day = period.day_of_week
            start = period.start_time
            end = period.end_time

            # ── Constraint 1: Lecturer availability ──────────────────────────
            if self._overlaps(day, start, end, self._lecturer_bookings[task.lecturer.id]):
                continue

            # ── Constraint 2: Student group availability ─────────────────────
            if self._overlaps(day, start, end, self._group_bookings[task.group.id]):
                continue

            # ── Constraints 3–6: Venue selection ────────────────────────────
            venue = self._find_venue(task.course, task.group, day, start, end)
            if venue is None:
                continue

            return {'period': period, 'venue': venue}

        return None  # no suitable slot exists

    def _find_venue(self, course, group, day: str, start: dtime, end: dtime) -> Optional[object]:
        """
        Select the most suitable venue — smallest capacity that still fits
        (venues are pre-sorted ascending by capacity).

        Constraints checked:
          3. capacity >= group.student_count
          4. venue_type matches course.required_venue_type (if specified)
          5. venue has all entries in course.required_resources
          6. venue has no overlapping booking at (day, start, end)
        """
        student_count = max(group.student_count, 1)  # treat 0 as 1
        required_type = (course.required_venue_type or '').strip()
        required_resources = set(course.required_resources or [])

        for venue in self._venues:
            # 3. Capacity
            if venue.capacity < student_count:
                continue
            # 4. Venue type
            if required_type and venue.venue_type != required_type:
                continue
            # 5. Required resources
            if required_resources and not required_resources.issubset(
                set(venue.resources or [])
            ):
                continue
            # 6. Venue availability (overlap check)
            if self._overlaps(day, start, end, self._venue_bookings[venue.id]):
                continue

            return venue  # first (closest-fit) venue found

        return None

    # ── Diagnostics ───────────────────────────────────────────────────────────

    def _diagnose_failure(self, task: SchedulingTask) -> str:
        """
        Explain why no period could be found for a task.
        Tries each period to identify the dominant constraint.
        """
        lecturer_blocked = 0
        group_blocked = 0
        no_venue = 0

        for period in self._periods:
            day, start, end = period.day_of_week, period.start_time, period.end_time

            if self._overlaps(day, start, end, self._lecturer_bookings[task.lecturer.id]):
                lecturer_blocked += 1
                continue
            if self._overlaps(day, start, end, self._group_bookings[task.group.id]):
                group_blocked += 1
                continue
            # Lecturer and group were free — venue is the problem
            venue = self._find_venue(task.course, task.group, day, start, end)
            if venue is None:
                no_venue += 1

        parts = []
        if not self._periods:
            return 'No active teaching periods defined for this semester.'
        if lecturer_blocked == len(self._periods):
            parts.append('Lecturer fully booked in all teaching periods')
        elif lecturer_blocked > 0:
            parts.append(f'Lecturer conflict in {lecturer_blocked} period(s)')
        if group_blocked > 0:
            parts.append(f'Student group conflict in {group_blocked} period(s)')
        if no_venue > 0:
            parts.append(
                f'No venue satisfies capacity/type/resource requirements '
                f'in {no_venue} otherwise-free period(s)'
            )
        return '; '.join(parts) if parts else 'No available teaching period found.'
