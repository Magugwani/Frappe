from django.db import models
from accounts.models import User


class AcademicYear(models.Model):
    class Status(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        INACTIVE = 'INACTIVE', 'Inactive'
        COMPLETED = 'COMPLETED', 'Completed'

    name = models.CharField(max_length=20, unique=True)  # e.g. "2026/2027"
    start_date = models.DateField()
    end_date = models.DateField()
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.INACTIVE)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'academic_years'
        ordering = ['-start_date']

    def __str__(self):
        return self.name

    @property
    def is_active(self):
        return self.status == self.Status.ACTIVE


class Semester(models.Model):
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.CASCADE, related_name='semesters')
    name = models.CharField(max_length=50)  # e.g. "Semester One"
    start_date = models.DateField()
    end_date = models.DateField()
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'semesters'
        unique_together = ['academic_year', 'name']
        ordering = ['academic_year', 'start_date']

    def __str__(self):
        return f'{self.academic_year.name} — {self.name}'


class Department(models.Model):
    name = models.CharField(max_length=200)
    code = models.CharField(max_length=20, unique=True)

    class Meta:
        db_table = 'departments'
        ordering = ['name']

    def __str__(self):
        return f'{self.code} — {self.name}'


class Programme(models.Model):
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name='programmes')
    name = models.CharField(max_length=200)
    code = models.CharField(max_length=20, unique=True)
    duration_years = models.PositiveIntegerField(default=3)

    class Meta:
        db_table = 'programmes'
        ordering = ['name']

    def __str__(self):
        return f'{self.code} — {self.name}'


class StudentGroup(models.Model):
    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name='student_groups')
    year_of_study = models.PositiveIntegerField()
    group_name = models.CharField(max_length=50)  # e.g. "Group A"
    # Phase 4 additions
    academic_year = models.ForeignKey(
        'AcademicYear', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='student_groups'
    )
    student_count = models.PositiveIntegerField(
        default=0,
        help_text='Expected number of students in this group. '
                  'Used by the timetable generator for venue capacity matching.'
    )

    class Meta:
        db_table = 'student_groups'
        unique_together = ['programme', 'year_of_study', 'group_name']
        ordering = ['programme', 'year_of_study', 'group_name']

    def __str__(self):
        return f'{self.programme.code} Year {self.year_of_study} {self.group_name}'

    @property
    def display_name(self):
        return str(self)


class Course(models.Model):
    course_code = models.CharField(max_length=20, unique=True)
    course_name = models.CharField(max_length=200)
    programme = models.ForeignKey(Programme, on_delete=models.CASCADE, related_name='courses')
    semester = models.ForeignKey(
        Semester, on_delete=models.SET_NULL, null=True, blank=True, related_name='courses'
    )
    year_of_study = models.PositiveIntegerField(default=1)
    credit_hours = models.PositiveIntegerField(default=3)
    weekly_hours = models.PositiveIntegerField(default=3)
    required_venue_type = models.CharField(max_length=50, blank=True)
    required_resources = models.JSONField(default=list, blank=True)

    class Meta:
        db_table = 'courses'
        ordering = ['course_code']

    def __str__(self):
        return f'{self.course_code} — {self.course_name}'


class TeachingPeriod(models.Model):
    """
    Defines a specific time slot when teaching can occur.

    The timetable generator (Phase 5) uses these as the candidate positions
    into which courses are placed. The coordinator defines them per semester
    before generation begins.

    Example records for a semester:
      Monday    08:00–10:00
      Monday    10:00–12:00
      Tuesday   08:00–10:00
      Tuesday   13:00–15:00

    Rules enforced at generation time (not here):
    - A lecturer cannot be placed in two overlapping TeachingPeriods.
    - A student group cannot appear in two overlapping TeachingPeriods.
    - A venue cannot be double-booked within the same TeachingPeriod.
    """

    class DayOfWeek(models.TextChoices):
        MONDAY = 'MONDAY', 'Monday'
        TUESDAY = 'TUESDAY', 'Tuesday'
        WEDNESDAY = 'WEDNESDAY', 'Wednesday'
        THURSDAY = 'THURSDAY', 'Thursday'
        FRIDAY = 'FRIDAY', 'Friday'
        SATURDAY = 'SATURDAY', 'Saturday'

    semester = models.ForeignKey(
        Semester, on_delete=models.CASCADE, related_name='teaching_periods'
    )
    day_of_week = models.CharField(max_length=10, choices=DayOfWeek.choices)
    start_time = models.TimeField()
    end_time = models.TimeField()
    label = models.CharField(
        max_length=50, blank=True,
        help_text='Optional human-readable label, e.g. "Period 1". '
                  'Auto-generated from day + time if left blank.'
    )
    is_active = models.BooleanField(
        default=True,
        help_text='Inactive periods are excluded from timetable generation.'
    )

    class Meta:
        db_table = 'teaching_periods'
        unique_together = ['semester', 'day_of_week', 'start_time']
        ordering = ['day_of_week', 'start_time']

    def __str__(self):
        if self.label:
            return self.label
        start = self.start_time.strftime('%H:%M')
        end = self.end_time.strftime('%H:%M')
        return f'{self.get_day_of_week_display()} {start}–{end}'

    @property
    def duration_minutes(self):
        s = self.start_time.hour * 60 + self.start_time.minute
        e = self.end_time.hour * 60 + self.end_time.minute
        return e - s


class Lecturer(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='lecturer_profile')
    staff_number = models.CharField(max_length=50, unique=True)
    department = models.ForeignKey(
        Department, on_delete=models.SET_NULL, null=True, blank=True, related_name='lecturers'
    )
    courses = models.ManyToManyField(
        Course, blank=True, related_name='assigned_lecturers',
        through='LecturerCourse'
    )

    class Meta:
        db_table = 'lecturers'
        ordering = ['user__full_name']

    def __str__(self):
        return f'{self.user.full_name} ({self.staff_number})'


class LecturerCourse(models.Model):
    """Through model for Lecturer ↔ Course assignment."""
    lecturer = models.ForeignKey(Lecturer, on_delete=models.CASCADE, related_name='course_assignments')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='lecturer_assignments')
    academic_year = models.ForeignKey(
        AcademicYear, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='lecturer_courses'
    )
    assigned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'lecturer_courses'
        unique_together = ['lecturer', 'course', 'academic_year']

    def __str__(self):
        return f'{self.lecturer} → {self.course}'


class StudentProfile(models.Model):
    """
    Minimal student identity record.
    Links a User (role=STUDENT) to their academic placement.
    Used by the timetable system to auto-filter entries without
    requiring the student to manually select programme/group every time.
    Full student enrollment (registration, CSV import) comes in a later phase.
    """
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='student_profile')
    registration_number = models.CharField(max_length=50, unique=True)
    programme = models.ForeignKey(
        Programme, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='student_profiles'
    )
    student_group = models.ForeignKey(
        StudentGroup, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='student_profiles'
    )

    class Meta:
        db_table = 'student_profiles'
        ordering = ['user__full_name']

    def __str__(self):
        return f'{self.user.full_name} ({self.registration_number})'
