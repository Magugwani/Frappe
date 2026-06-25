from django.db import models


class Building(models.Model):
    name = models.CharField(max_length=200)
    address = models.TextField(blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'buildings'
        ordering = ['name']

    def __str__(self):
        return self.name


class Venue(models.Model):
    class VenueType(models.TextChoices):
        LECTURE_HALL = 'LECTURE_HALL', 'Lecture Hall'
        CLASSROOM = 'CLASSROOM', 'Classroom'
        LABORATORY = 'LABORATORY', 'Laboratory'
        COMPUTER_LAB = 'COMPUTER_LAB', 'Computer Lab'
        SEMINAR_ROOM = 'SEMINAR_ROOM', 'Seminar Room'
        AUDITORIUM = 'AUDITORIUM', 'Auditorium'

    class Status(models.TextChoices):
        FREE = 'FREE', 'Free'
        BOOKED = 'BOOKED', 'Booked'
        IN_USE = 'IN_USE', 'In Use'
        EXPIRED = 'EXPIRED', 'Expired'
        MAINTENANCE = 'MAINTENANCE', 'Under Maintenance'

    code = models.CharField(max_length=20, unique=True)
    name = models.CharField(max_length=200)
    building = models.ForeignKey(Building, on_delete=models.CASCADE, related_name='venues')
    floor = models.IntegerField(default=0)
    capacity = models.PositiveIntegerField()
    venue_type = models.CharField(max_length=20, choices=VenueType.choices)
    resources = models.JSONField(default=list, blank=True)       # e.g. ["projector","computer"]
    accessibility = models.JSONField(default=list, blank=True)   # e.g. ["wheelchair_access"]
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.FREE)
    is_active = models.BooleanField(default=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'venues'
        ordering = ['building', 'code']

    def __str__(self):
        return f'{self.code} — {self.name} ({self.building.name})'


# ── Phase 8: Venue Status History ─────────────────────────────────────────────

class VenueStatusHistory(models.Model):
    venue      = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name='status_history')
    old_status = models.CharField(max_length=20, choices=Venue.Status.choices)
    new_status = models.CharField(max_length=20, choices=Venue.Status.choices)
    changed_by = models.ForeignKey('accounts.User', on_delete=models.SET_NULL, null=True)
    changed_at = models.DateTimeField(auto_now_add=True)
    reason     = models.TextField(blank=True)
    timetable_entry = models.ForeignKey(
        'timetable.TimetableEntry', on_delete=models.SET_NULL,
        null=True, blank=True, related_name='venue_status_changes',
    )

    class Meta:
        db_table = 'venue_status_history'
        ordering = ['-changed_at']

    def __str__(self):
        return f'{self.venue.code}: {self.old_status}→{self.new_status} by {self.changed_by}'
