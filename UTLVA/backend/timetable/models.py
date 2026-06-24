from django.db import models
from accounts.models import User
from academics.models import AcademicYear, Semester, Programme, StudentGroup, Course, Lecturer
from venues.models import Venue


class DayOfWeek(models.TextChoices):
    MONDAY = 'MONDAY', 'Monday'
    TUESDAY = 'TUESDAY', 'Tuesday'
    WEDNESDAY = 'WEDNESDAY', 'Wednesday'
    THURSDAY = 'THURSDAY', 'Thursday'
    FRIDAY = 'FRIDAY', 'Friday'
    SATURDAY = 'SATURDAY', 'Saturday'


class TimetableStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Draft'
    VALIDATED = 'VALIDATED', 'Validated'   # Phase 6: passed conflict check
    PUBLISHED = 'PUBLISHED', 'Published'


class TimetableEntry(models.Model):
    # Academic context
    academic_year = models.ForeignKey(
        AcademicYear, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    semester = models.ForeignKey(
        Semester, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    programme = models.ForeignKey(
        Programme, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    student_group = models.ForeignKey(
        StudentGroup, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='timetable_entries'
    )

    # Teaching assignment
    course = models.ForeignKey(
        Course, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    lecturer = models.ForeignKey(
        Lecturer, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    venue = models.ForeignKey(
        Venue, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='timetable_entries'
    )

    # Scheduling
    day_of_week = models.CharField(max_length=10, choices=DayOfWeek.choices)
    date = models.DateField(null=True, blank=True)  # optional specific date override
    start_time = models.TimeField()
    end_time = models.TimeField()

    # Lifecycle: DRAFT → VALIDATED → PUBLISHED
    status = models.CharField(
        max_length=20, choices=TimetableStatus.choices, default=TimetableStatus.DRAFT
    )

    # Audit
    created_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='created_timetable_entries'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'timetable_entries'
        ordering = ['day_of_week', 'start_time']

    def __str__(self):
        return (
            f'{self.course.course_code} | {self.day_of_week} '
            f'{self.start_time}-{self.end_time} | {self.status}'
        )

    @property
    def duration_minutes(self):
        start = self.start_time.hour * 60 + self.start_time.minute
        end = self.end_time.hour * 60 + self.end_time.minute
        return end - start


class TimetableConflict(models.Model):
    """
    Records a detected conflict between two TimetableEntry objects.

    Conflicts are (re)created each time the validation engine runs.
    OPEN conflicts block promotion to VALIDATED.
    RESOLVED conflicts are kept for audit purposes.
    """

    class ConflictType(models.TextChoices):
        VENUE = 'VENUE_CONFLICT', 'Venue Conflict'
        LECTURER = 'LECTURER_CONFLICT', 'Lecturer Conflict'
        STUDENT_GROUP = 'STUDENT_GROUP_CONFLICT', 'Student Group Conflict'

    class Status(models.TextChoices):
        OPEN = 'OPEN', 'Open'
        RESOLVED = 'RESOLVED', 'Resolved'

    conflict_type = models.CharField(max_length=30, choices=ConflictType.choices)
    timetable_entry_a = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='conflicts_as_a'
    )
    timetable_entry_b = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='conflicts_as_b'
    )
    message = models.TextField()
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.OPEN
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'timetable_conflicts'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.conflict_type} | {self.timetable_entry_a} ↔ {self.timetable_entry_b}'
