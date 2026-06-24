from django.core.management.base import BaseCommand
from datetime import time
from academics.models import Semester, TeachingPeriod, StudentGroup, AcademicYear


class Command(BaseCommand):
    help = 'Seed standard teaching periods for active semesters'

    def handle(self, *args, **options):
        try:
            year = AcademicYear.objects.get(name='2025/2026')
            sem = Semester.objects.get(academic_year=year, name='Semester One')
        except (AcademicYear.DoesNotExist, Semester.DoesNotExist):
            self.stdout.write(self.style.ERROR('Run seed_academics first.'))
            return

        # Standard teaching periods: Mon–Fri, four 2-hour blocks
        days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY']
        slots = [
            (time(8, 0), time(10, 0)),
            (time(10, 0), time(12, 0)),
            (time(13, 0), time(15, 0)),
            (time(15, 0), time(17, 0)),
        ]

        created = 0
        for day in days:
            for i, (start, end) in enumerate(slots, 1):
                label = f'{day.capitalize()[:3]} Period {i} ({start.strftime("%H:%M")}–{end.strftime("%H:%M")})'
                _, was_created = TeachingPeriod.objects.get_or_create(
                    semester=sem, day_of_week=day, start_time=start,
                    defaults={'end_time': end, 'label': label, 'is_active': True},
                )
                if was_created:
                    created += 1

        self.stdout.write(self.style.SUCCESS(
            f'Created {created} teaching periods for {sem}.'
        ))
        self.stdout.write(f'  Total periods: {TeachingPeriod.objects.filter(semester=sem).count()}')

        # Also update StudentGroups with academic_year and example student_count
        updated = StudentGroup.objects.filter(academic_year__isnull=True).update(
            academic_year=year,
        )
        # Set example student counts
        for group in StudentGroup.objects.filter(academic_year=year):
            if group.student_count == 0:
                group.student_count = 45  # default count
                group.save(update_fields=['student_count'])

        self.stdout.write(f'  Updated {updated} student groups with academic_year={year}')
        self.stdout.write(self.style.SUCCESS('Done.'))
