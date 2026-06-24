from django.core.management.base import BaseCommand
from django.utils.timezone import now
from datetime import date
from academics.models import (
    AcademicYear, Semester, Department, Programme,
    StudentGroup, Course, Lecturer, LecturerCourse,
)
from venues.models import Building, Venue
from accounts.models import User, Role


class Command(BaseCommand):
    help = 'Seed Phase 2 academic and venue master data'

    def handle(self, *args, **options):
        self.stdout.write('Seeding academic master data...')

        # Academic Year
        year, _ = AcademicYear.objects.get_or_create(
            name='2025/2026',
            defaults={
                'start_date': date(2025, 9, 1),
                'end_date': date(2026, 6, 30),
                'status': AcademicYear.Status.ACTIVE,
            },
        )
        self.stdout.write(f'  AcademicYear: {year}')

        # Semesters
        sem1, _ = Semester.objects.get_or_create(
            academic_year=year, name='Semester One',
            defaults={'start_date': date(2025, 9, 1), 'end_date': date(2026, 1, 31)},
        )
        sem2, _ = Semester.objects.get_or_create(
            academic_year=year, name='Semester Two',
            defaults={'start_date': date(2026, 2, 1), 'end_date': date(2026, 6, 30)},
        )
        self.stdout.write(f'  Semesters: {sem1.name}, {sem2.name}')

        # Department
        dept, _ = Department.objects.get_or_create(
            code='CCT',
            defaults={'name': 'Computing and Communication Technology'},
        )
        self.stdout.write(f'  Department: {dept}')

        # Programme
        prog, _ = Programme.objects.get_or_create(
            code='BIT',
            defaults={'name': 'Bachelor of Information Technology', 'department': dept, 'duration_years': 3},
        )
        self.stdout.write(f'  Programme: {prog}')

        # Student Groups
        for grp in ['Group A', 'Group B']:
            for yr in [1, 2, 3]:
                StudentGroup.objects.get_or_create(
                    programme=prog, year_of_study=yr, group_name=grp
                )
        self.stdout.write('  StudentGroups: BIT Year 1-3 Group A/B')

        # Courses
        courses_data = [
            ('BIT101', 'Introduction to Programming', 1, sem1, 3, 4, 'COMPUTER_LAB'),
            ('BIT102', 'Mathematics for Computing', 1, sem1, 3, 3, 'CLASSROOM'),
            ('BIT201', 'Database Systems', 2, sem1, 3, 4, 'COMPUTER_LAB'),
            ('BIT202', 'Software Engineering', 2, sem2, 3, 3, 'LECTURE_HALL'),
            ('BIT301', 'Final Year Project', 3, sem2, 6, 2, 'SEMINAR_ROOM'),
        ]
        for code, name, yr, sem, credits, weekly, vtype in courses_data:
            Course.objects.get_or_create(
                course_code=code,
                defaults={
                    'course_name': name, 'programme': prog, 'semester': sem,
                    'year_of_study': yr, 'credit_hours': credits,
                    'weekly_hours': weekly, 'required_venue_type': vtype,
                },
            )
        self.stdout.write('  Courses: 5 courses created')

        # Lecturer profile for existing lecturer user
        try:
            lect_user = User.objects.get(email='lecturer@utlva.ac.tz')
            lect, _ = Lecturer.objects.get_or_create(
                user=lect_user,
                defaults={'staff_number': 'STAFF001', 'department': dept},
            )
            # Assign first two courses
            for course in Course.objects.filter(course_code__in=['BIT101', 'BIT201']):
                LecturerCourse.objects.get_or_create(lecturer=lect, course=course, academic_year=year)
            self.stdout.write(f'  Lecturer profile: {lect}')
        except User.DoesNotExist:
            self.stdout.write(self.style.WARNING('  Lecturer user not found — run seed_users first'))

        # Buildings
        b1, _ = Building.objects.get_or_create(
            name='Block A — Main Academic Block',
            defaults={'address': 'Main Campus, Dar es Salaam', 'latitude': -6.7717, 'longitude': 39.2736},
        )
        b2, _ = Building.objects.get_or_create(
            name='Block B — Science Block',
            defaults={'address': 'Main Campus, Dar es Salaam', 'latitude': -6.7720, 'longitude': 39.2740},
        )
        self.stdout.write(f'  Buildings: {b1.name}, {b2.name}')

        # Venues
        venues_data = [
            ('LH-A101', 'Lecture Hall A101', b1, 0, 120, 'LECTURE_HALL', ['projector', 'whiteboard']),
            ('CR-A201', 'Classroom A201', b1, 2, 40, 'CLASSROOM', ['whiteboard']),
            ('CL-B101', 'Computer Lab B101', b2, 1, 60, 'COMPUTER_LAB', ['computers', 'projector']),
            ('SR-A301', 'Seminar Room A301', b1, 3, 20, 'SEMINAR_ROOM', ['projector']),
            ('LB-B201', 'Science Laboratory', b2, 2, 30, 'LABORATORY', ['lab_equipment']),
        ]
        for code, name, bldg, floor, cap, vtype, resources in venues_data:
            Venue.objects.get_or_create(
                code=code,
                defaults={
                    'name': name, 'building': bldg, 'floor': floor,
                    'capacity': cap, 'venue_type': vtype, 'resources': resources,
                },
            )
        self.stdout.write('  Venues: 5 venues created')

        self.stdout.write(self.style.SUCCESS('\nPhase 2 seed data complete.'))
