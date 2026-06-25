# Generated for Phase 8 — SystemConfiguration, EmergencySession, TimetableEntry new fields

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academics', '0003_semester_is_active_studentgroup_academic_year_and_more'),
        ('timetable', '0003_timetableconflict_resolution_note_and_more'),
        ('venues', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        # ── New fields on TimetableEntry ───────────────────────────────────────
        migrations.AddField(
            model_name='timetableentry',
            name='expected_student_count',
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='timetableentry',
            name='venue_override_by',
            field=models.ForeignKey(
                blank=True, null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='venue_overrides',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name='timetableentry',
            name='venue_override_reason',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='timetableentry',
            name='venue_override_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        # ── SystemConfiguration singleton ──────────────────────────────────────
        migrations.CreateModel(
            name='SystemConfiguration',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('capacity_overhead', models.FloatField(
                    default=1.5,
                    help_text='Multiplier for maximum venue capacity. Example: 100 students → allow up to 150-capacity venues.',
                )),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('updated_by', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'db_table': 'system_configuration',
            },
        ),
        # ── EmergencySession ───────────────────────────────────────────────────
        migrations.CreateModel(
            name='EmergencySession',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('requested_date', models.DateField()),
                ('day_of_week', models.CharField(
                    choices=[
                        ('MONDAY', 'Monday'), ('TUESDAY', 'Tuesday'),
                        ('WEDNESDAY', 'Wednesday'), ('THURSDAY', 'Thursday'),
                        ('FRIDAY', 'Friday'), ('SATURDAY', 'Saturday'),
                    ],
                    max_length=10,
                )),
                ('start_time', models.TimeField()),
                ('end_time', models.TimeField()),
                ('reason', models.TextField(help_text='Why this emergency session is needed.')),
                ('status', models.CharField(
                    choices=[
                        ('PENDING', 'Pending Review'), ('APPROVED', 'Approved'),
                        ('REJECTED', 'Rejected'), ('CANCELLED', 'Cancelled'),
                    ],
                    default='PENDING',
                    max_length=20,
                )),
                ('reviewed_at', models.DateTimeField(blank=True, null=True)),
                ('review_note', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('lecturer_conflict', models.BooleanField(default=False)),
                ('venue_conflict', models.BooleanField(default=False)),
                ('group_conflict', models.BooleanField(default=False)),
                ('course', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='emergency_sessions',
                    to='academics.course',
                )),
                ('lecturer', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='emergency_sessions',
                    to='academics.lecturer',
                )),
                ('venue', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='emergency_sessions',
                    to='venues.venue',
                )),
                ('student_groups', models.ManyToManyField(
                    blank=True,
                    related_name='emergency_sessions',
                    to='academics.studentgroup',
                )),
                ('requested_by', models.ForeignKey(
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='requested_emergency_sessions',
                    to=settings.AUTH_USER_MODEL,
                )),
                ('reviewed_by', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='reviewed_emergency_sessions',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'db_table': 'emergency_sessions',
                'ordering': ['-created_at'],
            },
        ),
        # ── PostgreSQL exclusion constraint placeholder ─────────────────────────
        migrations.RunSQL(
            sql="""
            -- Phase 8: Exclusion constraint placeholder.
            -- To enable PostgreSQL exclusion constraint for concurrent booking protection:
            --   CREATE EXTENSION IF NOT EXISTS btree_gist;
            -- Then add constraint via ALTER TABLE. Enabled when concurrency is a concern.
            -- This migration records the intent for future activation.
            SELECT 1;  -- no-op placeholder
            """,
            reverse_sql="SELECT 1;",
        ),
    ]
