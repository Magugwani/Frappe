"""
Venues Phase 2 migration: full venue management module (SRS §3.3).

Adds:
  • Building: code (unique nullable), description, is_active, updated_at
  • Venue:    description, indoor_identifier, OFFICE venue type, indexes
  • VenueStatusHistory: full audit table

Safe to run on an empty database (the unique-nullable approach also allows
running on a populated database where buildings already exist).
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('venues', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        # ── Building ───────────────────────────────────────────────────────
        # `code` may already exist on a populated DB (added by a now-deleted
        # hotfix migration). SeparateDatabaseAndState lets Django track the
        # model state change while using IF NOT EXISTS so it never crashes.
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AddField(
                    model_name='building',
                    name='code',
                    field=models.CharField(
                        blank=True, max_length=20, null=True, unique=True,
                        help_text='Short code, e.g. "COICT", "ECT", "LIB-A". '
                                  'Used as the human-readable identifier on the map.',
                    ),
                ),
            ],
            database_operations=[
                migrations.RunSQL(
                    sql='ALTER TABLE buildings ADD COLUMN IF NOT EXISTS '
                        'code VARCHAR(20) NULL;',
                    reverse_sql='ALTER TABLE buildings DROP COLUMN IF EXISTS code;',
                ),
            ],
        ),
        migrations.AddField(
            model_name='building',
            name='description',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='building',
            name='is_active',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='building',
            name='updated_at',
            field=models.DateTimeField(auto_now=True),
        ),

        # ── Venue ──────────────────────────────────────────────────────────
        migrations.AlterField(
            model_name='venue',
            name='code',
            field=models.CharField(
                max_length=30, unique=True,
                help_text='Unique short identifier, e.g. "COICT-LH1", "ECT-LAB-3".',
            ),
        ),
        migrations.AddField(
            model_name='venue',
            name='description',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='venue',
            name='indoor_identifier',
            field=models.CharField(
                blank=True, max_length=100,
                help_text='Optional wayfinding hint, e.g. "Wing A, near elevator", '
                          '"Room number 305".',
            ),
        ),
        migrations.AlterField(
            model_name='venue',
            name='venue_type',
            field=models.CharField(
                max_length=20,
                choices=[
                    ('LECTURE_HALL', 'Lecture Hall'),
                    ('CLASSROOM', 'Classroom'),
                    ('LABORATORY', 'Laboratory'),
                    ('COMPUTER_LAB', 'Computer Lab'),
                    ('SEMINAR_ROOM', 'Seminar Room'),
                    ('AUDITORIUM', 'Auditorium'),
                    ('OFFICE', 'Office'),
                ],
            ),
        ),
        migrations.AlterField(
            model_name='venue',
            name='resources',
            field=models.JSONField(
                blank=True, default=list,
                help_text='List of strings, e.g. ["projector", "audio_system", '
                          '"whiteboard", "smart_board", "computers_30"].',
            ),
        ),
        migrations.AlterField(
            model_name='venue',
            name='accessibility',
            field=models.JSONField(
                blank=True, default=list,
                help_text='List of accessibility features, e.g. '
                          '["wheelchair_access", "hearing_loop", "ramp", "elevator_access"].',
            ),
        ),
        migrations.AlterField(
            model_name='venue',
            name='is_active',
            field=models.BooleanField(
                default=True,
                help_text='When False, the venue is invisible to the auto-booking engine '
                          'and to "find available rooms" search. Deactivation with future '
                          'bookings is blocked at the service layer.',
            ),
        ),
        migrations.AlterModelOptions(
            name='venue',
            options={'ordering': ['building__name', 'code']},
        ),
        migrations.AddIndex(
            model_name='venue',
            index=models.Index(fields=['status'], name='venues_status_idx'),
        ),
        migrations.AddIndex(
            model_name='venue',
            index=models.Index(fields=['venue_type'], name='venues_type_idx'),
        ),
        migrations.AddIndex(
            model_name='venue',
            index=models.Index(fields=['is_active', 'status'], name='venues_active_status_idx'),
        ),
        migrations.AddIndex(
            model_name='venue',
            index=models.Index(fields=['building', 'floor'], name='venues_bldg_floor_idx'),
        ),

        # ── VenueStatusHistory ─────────────────────────────────────────────
        # Drop the Phase-8 venue_status_history table (old schema: old_status,
        # changed_by_id, timetable_entry_id) so this migration can create the
        # authoritative schema with triggered_by_event and full audit fields.
        migrations.RunSQL(
            sql='DROP TABLE IF EXISTS venue_status_history CASCADE;',
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.CreateModel(
            name='VenueStatusHistory',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True,
                                            serialize=False, verbose_name='ID')),
                ('previous_status', models.CharField(
                    blank=True, null=True, max_length=20,
                    choices=[
                        ('FREE', 'Free'), ('BOOKED', 'Booked'),
                        ('IN_USE', 'In Use'), ('EXPIRED', 'Expired'),
                        ('MAINTENANCE', 'Under Maintenance'),
                    ],
                    help_text='Null only for the very first record (post-creation seed).',
                )),
                ('new_status', models.CharField(
                    max_length=20,
                    choices=[
                        ('FREE', 'Free'), ('BOOKED', 'Booked'),
                        ('IN_USE', 'In Use'), ('EXPIRED', 'Expired'),
                        ('MAINTENANCE', 'Under Maintenance'),
                    ],
                )),
                ('triggered_by_event', models.CharField(
                    max_length=50,
                    choices=[
                        ('TIMETABLE_ENTRY_CREATED', 'Timetable entry created'),
                        ('EMERGENCY_SESSION_APPROVED', 'Emergency session approved'),
                        ('LECTURER_CONFIRMED', 'Lecturer confirmed session'),
                        ('CONFIRMATION_WINDOW_EXPIRED', 'Confirmation window expired'),
                        ('SESSION_CANCELLED', 'Session cancelled'),
                        ('SESSION_ENDED', 'Session reached end_time'),
                        ('AUTO_RELEASE', 'Auto-released after expiry'),
                        ('MAINTENANCE_STARTED', 'Maintenance started'),
                        ('MAINTENANCE_ENDED', 'Maintenance ended'),
                        ('MANUAL_OVERRIDE', 'Manual override by administrator'),
                        ('SEEDED', 'Initial state set during data seeding'),
                    ],
                )),
                ('related_object_type', models.CharField(blank=True, max_length=50)),
                ('related_object_id', models.CharField(blank=True, max_length=50)),
                ('reason', models.TextField(blank=True)),
                ('metadata', models.JSONField(blank=True, null=True)),
                ('changed_at', models.DateTimeField(auto_now_add=True)),
                ('venue', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='status_history',
                    to='venues.venue',
                )),
                ('triggered_by_user', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='venue_status_transitions',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                'db_table': 'venue_status_history',
                'ordering': ['-changed_at'],
                'verbose_name': 'Venue status history entry',
                'verbose_name_plural': 'Venue status history',
                'indexes': [
                    models.Index(fields=['venue', '-changed_at'],
                                 name='vsh_venue_chg_idx'),
                    models.Index(fields=['triggered_by_event'],
                                 name='vsh_event_idx'),
                ],
            },
        ),
    ]