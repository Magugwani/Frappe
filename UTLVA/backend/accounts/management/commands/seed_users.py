from django.core.management.base import BaseCommand
from accounts.models import User, Role


class Command(BaseCommand):
    help = 'Seed one test user per role for development'

    def handle(self, *args, **options):
        users = [
            {
                'email': 'admin@utlva.ac.tz',
                'full_name': 'System Administrator',
                'role': Role.SYSTEM_ADMIN,
                'password': 'Admin@1234',
                'is_staff': True,
                'is_superuser': True,
            },
            {
                'email': 'coordinator@utlva.ac.tz',
                'full_name': 'Timetable Coordinator',
                'role': Role.COORDINATOR,
                'password': 'Coord@1234',
            },
            {
                'email': 'lecturer@utlva.ac.tz',
                'full_name': 'Dr. Jane Lecturer',
                'role': Role.LECTURER,
                'password': 'Lect@1234',
            },
            {
                'email': 'student@utlva.ac.tz',
                'full_name': 'John Student',
                'role': Role.STUDENT,
                'password': 'Stud@1234',
            },
        ]

        for data in users:
            password = data.pop('password')
            user, created = User.objects.get_or_create(
                email=data['email'], defaults=data
            )
            if created:
                user.set_password(password)
                user.save()
                self.stdout.write(
                    self.style.SUCCESS(f'Created {user.role}: {user.email}')
                )
            else:
                self.stdout.write(f'Already exists: {user.email}')

        self.stdout.write(self.style.SUCCESS('\nTest users ready:'))
        self.stdout.write('  admin@utlva.ac.tz       / Admin@1234  (SYSTEM_ADMIN)')
        self.stdout.write('  coordinator@utlva.ac.tz / Coord@1234  (COORDINATOR)')
        self.stdout.write('  lecturer@utlva.ac.tz    / Lect@1234   (LECTURER)')
        self.stdout.write('  student@utlva.ac.tz     / Stud@1234   (STUDENT)')
