# Generated for Phase 8 — Venue Status History

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('venues', '0001_initial'),
        ('timetable', '0003_timetableconflict_resolution_note_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='VenueStatusHistory',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('old_status', models.CharField(
                    choices=[
                        ('FREE', 'Free'), ('BOOKED', 'Booked'), ('IN_USE', 'In Use'),
                        ('EXPIRED', 'Expired'), ('MAINTENANCE', 'Under Maintenance'),
                    ],
                    max_length=20,
                )),
                ('new_status', models.CharField(
                    choices=[
                        ('FREE', 'Free'), ('BOOKED', 'Booked'), ('IN_USE', 'In Use'),
                        ('EXPIRED', 'Expired'), ('MAINTENANCE', 'Under Maintenance'),
                    ],
                    max_length=20,
                )),
                ('changed_at', models.DateTimeField(auto_now_add=True)),
                ('reason', models.TextField(blank=True)),
                ('changed_by', models.ForeignKey(
                    null=True, on_delete=django.db.models.deletion.SET_NULL,
                    to=settings.AUTH_USER_MODEL,
                )),
                ('timetable_entry', models.ForeignKey(
                    blank=True, null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='venue_status_changes',
                    to='timetable.timetableentry',
                )),
                ('venue', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='status_history',
                    to='venues.venue',
                )),
            ],
            options={
                'db_table': 'venue_status_history',
                'ordering': ['-changed_at'],
            },
        ),
    ]
