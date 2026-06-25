"""
UTLVA — Venue Management and Navigation Module (SRS §3.3)

Data model
----------
Building 1 ──< Venue 1 ──< VenueStatusHistory

A Building is the parent container (named structure with its own GPS coordinates
and address). A Venue is a room inside a Building, inheriting the building-level
metadata and adding floor and indoor identifiers, total capacity, type, resources,
accessibility features, and the live booking status.

Status is the single source of truth (SRS §3.3): it lives only on `venues.status`
and is never duplicated in caches or auxiliary tables. The history table is an
audit trail of *transitions*, never a mirror of current state.

Status lifecycle (SRS Table 2)
------------------------------
    FREE ─── timetable entry created ───▶ BOOKED
    BOOKED ─── lecturer confirms ────────▶ IN_USE
    BOOKED ─── confirmation window passes ▶ EXPIRED ─▶ FREE   (same transaction)
    BOOKED ─── coordinator/lecturer cancels ▶ FREE
    IN_USE ─── scheduled end_time reached ▶ FREE

MAINTENANCE is an out-of-band operational state, distinct from the booking
lifecycle. Only a System Administrator can place a venue into or out of
MAINTENANCE; while in MAINTENANCE the venue is invisible to the auto-booking
engine and to dashboard filters that target "available rooms".

The legal-transition matrix is enforced at the service layer
(see venues.services.VenueStateMachine), not at the DB level — this allows
forced transitions by administrators with reason logging.
"""

from django.conf import settings
from django.db import models


# ── Choices ───────────────────────────────────────────────────────────────────

class VenueType(models.TextChoices):
    LECTURE_HALL = 'LECTURE_HALL', 'Lecture Hall'
    CLASSROOM = 'CLASSROOM', 'Classroom'
    LABORATORY = 'LABORATORY', 'Laboratory'
    COMPUTER_LAB = 'COMPUTER_LAB', 'Computer Lab'
    SEMINAR_ROOM = 'SEMINAR_ROOM', 'Seminar Room'
    AUDITORIUM = 'AUDITORIUM', 'Auditorium'
    OFFICE = 'OFFICE', 'Office'


class VenueStatus(models.TextChoices):
    FREE = 'FREE', 'Free'
    BOOKED = 'BOOKED', 'Booked'
    IN_USE = 'IN_USE', 'In Use'
    EXPIRED = 'EXPIRED', 'Expired'
    MAINTENANCE = 'MAINTENANCE', 'Under Maintenance'


# Side-effect events that drive transitions (kept loose for forward compatibility
# with the upcoming Session and EmergencySession workflows).
class TransitionEvent(models.TextChoices):
    TIMETABLE_ENTRY_CREATED = 'TIMETABLE_ENTRY_CREATED', 'Timetable entry created'
    EMERGENCY_SESSION_APPROVED = 'EMERGENCY_SESSION_APPROVED', 'Emergency session approved'
    LECTURER_CONFIRMED = 'LECTURER_CONFIRMED', 'Lecturer confirmed session'
    CONFIRMATION_WINDOW_EXPIRED = 'CONFIRMATION_WINDOW_EXPIRED', 'Confirmation window expired'
    SESSION_CANCELLED = 'SESSION_CANCELLED', 'Session cancelled'
    SESSION_ENDED = 'SESSION_ENDED', 'Session reached end_time'
    AUTO_RELEASE = 'AUTO_RELEASE', 'Auto-released after expiry'
    MAINTENANCE_STARTED = 'MAINTENANCE_STARTED', 'Maintenance started'
    MAINTENANCE_ENDED = 'MAINTENANCE_ENDED', 'Maintenance ended'
    MANUAL_OVERRIDE = 'MANUAL_OVERRIDE', 'Manual override by administrator'
    SEEDED = 'SEEDED', 'Initial state set during data seeding'


# Marker colours for the dashboard / map UI (also returned by the API so the
# Flutter app does not have to hardcode them).
STATUS_MARKER_COLOR = {
    VenueStatus.FREE: '#22c55e',         # green
    VenueStatus.BOOKED: '#f59e0b',       # amber
    VenueStatus.IN_USE: '#ef4444',       # red
    VenueStatus.EXPIRED: '#6b7280',      # gray (transient — should never linger)
    VenueStatus.MAINTENANCE: '#64748b',  # slate
}


# ── Building ──────────────────────────────────────────────────────────────────

class Building(models.Model):
    """
    Physical structure that houses one or more venues.

    The Building → Venue hierarchy lets the map view first orient the user
    to the building, then guide them to the specific room. Building-level
    coordinates are the entry-point / front-door location of the structure;
    venue-level coordinates (when set) refine to the room itself.
    """

    code = models.CharField(
        max_length=20, unique=True, null=True, blank=True,
        help_text='Short code, e.g. "COICT", "ECT", "LIB-A". '
                  'Used as the human-readable identifier on the map.',
    )
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    address = models.TextField(blank=True)
    latitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True,
        help_text='Entry-point latitude (WGS84).',
    )
    longitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True,
        help_text='Entry-point longitude (WGS84).',
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'buildings'
        ordering = ['name']

    def __str__(self):
        if self.code:
            return f'{self.code} — {self.name}'
        return self.name

    @property
    def has_coordinates(self):
        return self.latitude is not None and self.longitude is not None


# ── Venue ─────────────────────────────────────────────────────────────────────

class Venue(models.Model):
    """
    A room inside a Building. The status field is the live, single source of
    truth for whether the room is currently available, booked, in use, etc.
    The status field is never duplicated elsewhere; transitions are recorded
    in VenueStatusHistory but the *current* status is always read from here.
    """

    # Identity
    code = models.CharField(
        max_length=30, unique=True,
        help_text='Unique short identifier, e.g. "COICT-LH1", "ECT-LAB-3".',
    )
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    building = models.ForeignKey(
        Building, on_delete=models.CASCADE, related_name='venues',
    )

    # Indoor positioning
    floor = models.IntegerField(
        default=0,
        help_text='Floor number. 0 = ground floor; basements are negative.',
    )
    indoor_identifier = models.CharField(
        max_length=100, blank=True,
        help_text='Optional wayfinding hint, e.g. "Wing A, near elevator", '
                  '"Room number 305".',
    )

    # Capacity and type
    capacity = models.PositiveIntegerField()
    venue_type = models.CharField(max_length=20, choices=VenueType.choices)

    # Resources and accessibility (JSONB on PostgreSQL)
    resources = models.JSONField(
        default=list, blank=True,
        help_text='List of strings, e.g. ["projector", "audio_system", '
                  '"whiteboard", "smart_board", "computers_30"].',
    )
    accessibility = models.JSONField(
        default=list, blank=True,
        help_text='List of accessibility features, e.g. '
                  '["wheelchair_access", "hearing_loop", "ramp", "elevator_access"].',
    )

    # Live status — single source of truth (SRS §3.3)
    status = models.CharField(
        max_length=20, choices=VenueStatus.choices, default=VenueStatus.FREE,
    )
    is_active = models.BooleanField(
        default=True,
        help_text='When False, the venue is invisible to the auto-booking engine '
                  'and to "find available rooms" search. Deactivation with future '
                  'bookings is blocked at the service layer.',
    )

    # Coordinates (refine the building-level location, optional)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'venues'
        ordering = ['building__name', 'code']
        indexes = [
            models.Index(fields=['status']),
            models.Index(fields=['venue_type']),
            models.Index(fields=['is_active', 'status']),
            models.Index(fields=['building', 'floor']),
        ]

    def __str__(self):
        return f'{self.code} — {self.name} ({self.building.name})'

    # ── Convenience properties ────────────────────────────────────────────

    @property
    def status_marker_color(self):
        """Hex colour the Flutter map should use for this venue's marker."""
        return STATUS_MARKER_COLOR.get(self.status, '#9ca3af')

    @property
    def is_bookable(self):
        """True if the venue is in a state that admits a new booking."""
        return self.is_active and self.status == VenueStatus.FREE

    @property
    def effective_latitude(self):
        """Venue's own latitude if set, otherwise the building's."""
        return self.latitude if self.latitude is not None else self.building.latitude

    @property
    def effective_longitude(self):
        return self.longitude if self.longitude is not None else self.building.longitude

    @property
    def has_coordinates(self):
        return self.effective_latitude is not None and self.effective_longitude is not None

    def has_resources(self, required):
        """True if every item in `required` is present in self.resources."""
        if not required:
            return True
        return set(required).issubset(set(self.resources or []))

    def has_accessibility(self, required):
        """True if every item in `required` is present in self.accessibility."""
        if not required:
            return True
        return set(required).issubset(set(self.accessibility or []))


# ── Venue status history ──────────────────────────────────────────────────────

class VenueStatusHistory(models.Model):
    """
    Append-only audit trail of every venue status transition (SRS §3.3).

    A row is written for *every* legal transition, including the transient
    EXPIRED → FREE that occurs immediately after BOOKED → EXPIRED (yielding
    two rows in the same transaction). The most recent row for a venue does
    NOT necessarily match the venue's current status — there is always
    an exact match because the row is written *as part of* the transition.

    This table is used by utilisation analytics and the audit panel.
    """

    venue = models.ForeignKey(
        Venue, on_delete=models.CASCADE, related_name='status_history',
    )
    previous_status = models.CharField(
        max_length=20, choices=VenueStatus.choices,
        null=True, blank=True,
        help_text='Null only for the very first record (post-creation seed).',
    )
    new_status = models.CharField(max_length=20, choices=VenueStatus.choices)

    triggered_by_event = models.CharField(
        max_length=50, choices=TransitionEvent.choices,
        help_text='Coarse-grained event category that drove the transition.',
    )
    triggered_by_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL, null=True, blank=True,
        related_name='venue_status_transitions',
        help_text='User who initiated the transition. Null for system-driven '
                  'transitions (e.g. Celery Beat expiry checks).',
    )

    # Forward-compatible reference to the object that caused the transition.
    # When Sessions and EmergencySessions land, related_object_type will be
    # "Session" or "EmergencySession" and related_object_id will be the PK.
    related_object_type = models.CharField(max_length=50, blank=True)
    related_object_id = models.CharField(max_length=50, blank=True)

    reason = models.TextField(blank=True)
    metadata = models.JSONField(null=True, blank=True)

    changed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'venue_status_history'
        ordering = ['-changed_at']
        indexes = [
            models.Index(fields=['venue', '-changed_at']),
            models.Index(fields=['triggered_by_event']),
        ]
        verbose_name = 'Venue status history entry'
        verbose_name_plural = 'Venue status history'

    def __str__(self):
        prev = self.previous_status or '∅'
        return f'{self.venue.code}: {prev} → {self.new_status} @ {self.changed_at:%Y-%m-%d %H:%M}'