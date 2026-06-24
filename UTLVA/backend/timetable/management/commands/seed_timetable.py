from django.core.management.base import BaseCommand
from datetime import time
from accounts.models import User
from academics.models import AcademicYear, Semester, Programme, StudentGroup, Course, Lecturer
from venues.models import Venue
from timetable.models import TimetableEntry, DayOfWeek, TimetableStatus


class Command(BaseCommand):
    help = 'Seed sample timetable entries'

    def handle(self, *args, **options):
        try:
            year = AcademicYear.objects.get(name='2025/2026')
            sem1 = Semester.objects.get(academic_year=year, name='Semester One')
            prog = Programme.objects.get(code='BIT')
            group_a = StudentGroup.objects.get(programme=prog, year_of_study=2, group_name='Group A')
            group_b = StudentGroup.objects.get(programme=prog, year_of_study=2, group_name='Group B')
            lect = Lecturer.objects.get(staff_number='STAFF001')
            coordinator = User.objects.get(email='coordinator@utlva.ac.tz')

            bit201 = Course.objects.get(course_code='BIT201')
            bit202 = Course.objects.get(course_code='BIT202')
            bit101 = Course.objects.get(course_code='BIT101')

            lh = Venue.objects.get(code='LH-A101')
            cl = Venue.objects.get(code='CL-B101')
            cr = Venue.objects.get(code='CR-A201')

        except Exception as e:
            self.stdout.write(self.style.ERROR(f'Seed data missing: {e}'))
            self.stdout.write('Run seed_users and seed_academics first.')
            return

        entries = [
            # Monday: Database Systems for Year 2 Group A
            dict(academic_year=year, semester=sem1, programme=prog, student_group=group_a,
                 course=bit201, lecturer=lect, venue=cl, day_of_week=DayOfWeek.MONDAY,
                 start_time=time(8, 0), end_time=time(10, 0), status=TimetableStatus.PUBLISHED),
            # Monday: Software Engineering for Year 2 Group B
            dict(academic_year=year, semester=sem1, programme=prog, student_group=group_b,
                 course=bit202, lecturer=lect, venue=lh, day_of_week=DayOfWeek.MONDAY,
                 start_time=time(10, 0), end_time=time(12, 0), status=TimetableStatus.PUBLISHED),
            # Wednesday: Intro to Programming (Year 1 Group A)
            dict(academic_year=year, semester=sem1, programme=prog,
                 student_group=StudentGroup.objects.get(programme=prog, year_of_study=1, group_name='Group A'),
                 course=bit101, lecturer=lect, venue=cl, day_of_week=DayOfWeek.WEDNESDAY,
                 start_time=time(9, 0), end_time=time(11, 0), status=TimetableStatus.PUBLISHED),
            # Wednesday: Database Systems (Year 2 Group B)
            dict(academic_year=year, semester=sem1, programme=prog, student_group=group_b,
                 course=bit201, lecturer=lect, venue=cl, day_of_week=DayOfWeek.WEDNESDAY,
                 start_time=time(13, 0), end_time=time(15, 0), status=TimetableStatus.PUBLISHED),
            # Friday: Software Engineering (Year 2 Group A) — DRAFT
            dict(academic_year=year, semester=sem1, programme=prog, student_group=group_a,
                 course=bit202, lecturer=lect, venue=cr, day_of_week=DayOfWeek.FRIDAY,
                 start_time=time(10, 0), end_time=time(12, 0), status=TimetableStatus.DRAFT),
            # Tuesday: Intro to Programming (Year 1 Group B)
            dict(academic_year=year, semester=sem1, programme=prog,
                 student_group=StudentGroup.objects.get(programme=prog, year_of_study=1, group_name='Group B'),
                 course=bit101, lecturer=lect, venue=lh, day_of_week=DayOfWeek.TUESDAY,
                 start_time=time(14, 0), end_time=time(16, 0), status=TimetableStatus.PUBLISHED),
        ]

        created = 0
        for data in entries:
            entry, was_created = TimetableEntry.objects.get_or_create(
                course=data['course'],
                day_of_week=data['day_of_week'],
                start_time=data['start_time'],
                student_group=data.get('student_group'),
                defaults={**data, 'created_by': coordinator},
            )
            if was_created:
                created += 1

        self.stdout.write(self.style.SUCCESS(f'Created {created} timetable entries.'))
