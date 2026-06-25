"""
UTLVA — Venue management business logic.

This module owns:
  1. Status transition rules (legal-transition matrix + history recording).
  2. Safe deactivation that surfaces affected future bookings rather than
     silently invalidating them (SRS §3.12 "Deactivation of a venue with
     future bookings").
  3. Alternative-venue suggestion used by the postponement and emergency
     session workflows.

Everything that mutates `venue.status` MUST go through `VenueStateMachine`;
direct writes to `venue.status` are considered a bug.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, time as dtime
from typing import Iterable, List, Optional

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from accounts.models import AuditLog
from .models import (
    Venue,
    VenueStatus,
    VenueStatusHistory,
    TransitionEvent,
)


# ── Legal transition matrix (SRS §3.3) ────────────────────────────────────────

# Maps "from_status" → set of allowed "to_status" values.
# This is the canonical rulebook. Any transition not listed here is rejected
# (unless the caller passes force=True with SYSTEM_ADMIN privileges).
LEGAL_TRANSITIONS: dict[str, set[str]] = {
    VenueStatus.FREE: {
        VenueStatus.BOOKED,
        VenueStatus.MAINTENANCE,
    },
    VenueStatus.BOOKED: {
        VenueStatus.IN_USE,        # lecturer confirms
        VenueStatus.EXPIRED,       # confirmation window expires
        VenueStatus.FREE,          # cancellation before start_time
        VenueStatus.MAINTENANCE,   # emergency maintenance (admin force)
    },
    VenueStatus.IN_USE: {
        VenueStatus.FREE,          # session reaches end_time
        VenueStatus.MAINTENANCE,   # emergency mid-session (admin force)
    },
    VenueStatus.EXPIRED: {
        VenueStatus.FREE,          # immediate auto-release (same transaction)
    },
    VenueStatus.MAINTENANCE: {
        VenueStatus.FREE,          # maintenance ends
    },
}

# Some transitions REQUIRE force=True even with admin privileges, because they
# can lose data (e.g. ending a live session).
REQUIRES_FORCE = {
    (VenueStatus.BOOKED, VenueStatus.MAINTENANCE),
    (VenueStatus.IN_USE, VenueStatus.MAINTENANCE),
}


# ── Exceptions ────────────────────────────────────────────────────────────────

class VenueServiceError(Exception):
    """Base class for venue-service problems surfaced to the API."""

    code = 'VENUE_SERVICE_ERROR'

    def __init__(self, message: str, code: Optional[str] = None, details: Optional[dict] = None):
        super().__init__(message)
        self.message = message
        if code:
            self.code = code
        self.details = details or {}


class IllegalTransition(VenueServiceError):
    code = 'ILLEGAL_TRANSITION'


class TransitionRequiresForce(VenueServiceError):
    code = 'TRANSITION_REQUIRES_FORCE'


class VenueHasFutureBookings(VenueServiceError):
    code = 'VENUE_HAS_FUTURE_BOOKINGS'


# ── Result objects ────────────────────────────────────────────────────────────

@dataclass
class TransitionResult:
    venue_id: int
    venue_code: str
    previous_status: Optional[str]
    new_status: str
    history_ids: List[int] = field(default_factory=list)
    final_status: Optional[str] = None  # for composite transitions (e.g. EXPIRED→FREE)

    def to_dict(self):
        return {
            'venue_id': self.venue_id,
            'venue_code': self.venue_code,
            'previous_status': self.previous_status,
            'new_status': self.new_status,
            'final_status': self.final_status or self.new_status,
            'history_ids': self.history_ids,
        }


@dataclass
class AffectedBooking:
    """One future booking that would be orphaned by venue deactivation."""
    source_type: str          # "TimetableEntry" — will add "Session" later
    source_id: int
    course_code: str
    lecturer: str
    day_of_week: str
    start_time: str
    end_time: str
    description: str

    def to_dict(self):
        return {
            'source_type': self.source_type,
            'source_id': self.source_id,
            'course_code': self.course_code,
            'lecturer': self.lecturer,
            'day_of_week': self.day_of_week,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'description': self.description,
        }


# ── Venue state machine ───────────────────────────────────────────────────────

class VenueStateMachine:
    """
    The single supported way to mutate `venue.status`.

    Usage
    -----
        machine = VenueStateMachine(venue)
        result = machine.transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
            user=request.user,
            related_object_type='TimetableEntry',
            related_object_id='42',
        )

    For the composite expiry workflow (BOOKED → EXPIRED → FREE) use the
    helper `.expire_booking()` which writes both history rows in one
    transaction and leaves the venue at FREE.
    """

    def __init__(self, venue: Venue):
        self.venue = venue

    @transaction.atomic
    def transition(
        self,
        to_status: str,
        event: str,
        user=None,
        reason: str = '',
        related_object_type: str = '',
        related_object_id: str = '',
        metadata: Optional[dict] = None,
        force: bool = False,
    ) -> TransitionResult:
        """
        Move the venue from its current status to `to_status`.

        Raises IllegalTransition if the transition is not in
        LEGAL_TRANSITIONS, or TransitionRequiresForce if it is listed in
        REQUIRES_FORCE but `force=False`.

        Writes a VenueStatusHistory row and an AuditLog row on success.
        """
        # Lock the venue row so concurrent transitions serialise.
        venue = Venue.objects.select_for_update().get(pk=self.venue.pk)
        previous = venue.status

        if previous == to_status:
            # Idempotent — no-op but still useful to record nothing changed.
            return TransitionResult(
                venue_id=venue.id, venue_code=venue.code,
                previous_status=previous, new_status=to_status,
                final_status=to_status,
            )

        allowed = LEGAL_TRANSITIONS.get(previous, set())
        if to_status not in allowed and not force:
            raise IllegalTransition(
                f'Cannot transition venue {venue.code} from {previous} to {to_status}. '
                f'Allowed transitions from {previous}: {sorted(allowed) or "none"}.',
                details={
                    'venue_id': venue.id,
                    'venue_code': venue.code,
                    'from_status': previous,
                    'to_status': to_status,
                    'allowed': sorted(allowed),
                },
            )

        if (previous, to_status) in REQUIRES_FORCE and not force:
            raise TransitionRequiresForce(
                f'Transition {previous} → {to_status} requires force=True (admin only) '
                'because it can affect a live or pending session.',
                details={
                    'venue_id': venue.id,
                    'venue_code': venue.code,
                    'from_status': previous,
                    'to_status': to_status,
                },
            )

        # Apply the transition.
        venue.status = to_status
        venue.save(update_fields=['status', 'updated_at'])

        history = VenueStatusHistory.objects.create(
            venue=venue,
            previous_status=previous,
            new_status=to_status,
            triggered_by_event=event,
            triggered_by_user=user,
            related_object_type=related_object_type or '',
            related_object_id=related_object_id or '',
            reason=reason,
            metadata=metadata,
        )

        # Sync the in-memory instance the caller is holding.
        self.venue.status = to_status

        # System-wide audit log (FR-5).
        if user is not None or event == TransitionEvent.MANUAL_OVERRIDE:
            AuditLog.objects.create(
                user=user,
                action=f'VENUE_TRANSITION:{previous}->{to_status}',
                entity_type='Venue',
                entity_id=str(venue.id),
                before_state={'status': previous},
                after_state={'status': to_status},
                extra={
                    'event': event,
                    'reason': reason,
                    'forced': force,
                    'history_id': history.id,
                    'related_object_type': related_object_type,
                    'related_object_id': related_object_id,
                },
            )

        return TransitionResult(
            venue_id=venue.id,
            venue_code=venue.code,
            previous_status=previous,
            new_status=to_status,
            history_ids=[history.id],
            final_status=to_status,
        )

    @transaction.atomic
    def expire_booking(
        self,
        event: str = TransitionEvent.CONFIRMATION_WINDOW_EXPIRED,
        user=None,
        related_object_type: str = '',
        related_object_id: str = '',
        reason: str = '',
    ) -> TransitionResult:
        """
        Composite transition BOOKED → EXPIRED → FREE in a single transaction.

        Writes two history rows. Final venue status is FREE.
        Used by the confirmation-window expiry task.
        """
        # First leg: BOOKED → EXPIRED
        first = self.transition(
            to_status=VenueStatus.EXPIRED,
            event=event,
            user=user,
            reason=reason,
            related_object_type=related_object_type,
            related_object_id=related_object_id,
        )

        # Second leg: EXPIRED → FREE (auto-release)
        second = self.transition(
            to_status=VenueStatus.FREE,
            event=TransitionEvent.AUTO_RELEASE,
            user=user,
            reason='Automatic release after EXPIRED transient state.',
            related_object_type=related_object_type,
            related_object_id=related_object_id,
        )

        return TransitionResult(
            venue_id=first.venue_id,
            venue_code=first.venue_code,
            previous_status=first.previous_status,    # BOOKED
            new_status=VenueStatus.EXPIRED,
            history_ids=first.history_ids + second.history_ids,
            final_status=VenueStatus.FREE,
        )


# ── Safe deactivation ─────────────────────────────────────────────────────────

def find_future_bookings(venue: Venue) -> List[AffectedBooking]:
    """
    Return every future booking that references this venue.

    Today this checks `timetable_entries`. Once Session and EmergencySession
    tables exist, extend this function to consult them too; the API contract
    is unchanged.
    """
    # Local import — avoids a circular import between venues and timetable.
    from timetable.models import TimetableEntry, TimetableStatus

    today = timezone.localdate()

    qs = TimetableEntry.objects.filter(
        venue=venue,
    ).filter(
        Q(date__isnull=True) | Q(date__gte=today)
    ).filter(
        status__in=[TimetableStatus.VALIDATED, TimetableStatus.PUBLISHED],
    ).select_related('course', 'lecturer__user')

    affected: List[AffectedBooking] = []
    for entry in qs:
        lecturer_name = (
            entry.lecturer.user.full_name if entry.lecturer and entry.lecturer.user
            else 'Unassigned'
        )
        affected.append(
            AffectedBooking(
                source_type='TimetableEntry',
                source_id=entry.id,
                course_code=entry.course.course_code if entry.course else '—',
                lecturer=lecturer_name,
                day_of_week=entry.day_of_week,
                start_time=entry.start_time.strftime('%H:%M') if entry.start_time else '',
                end_time=entry.end_time.strftime('%H:%M') if entry.end_time else '',
                description=(
                    f'{entry.course.course_code if entry.course else ""} • '
                    f'{entry.day_of_week} {entry.start_time:%H:%M}–{entry.end_time:%H:%M}'
                ),
            )
        )
    return affected


@transaction.atomic
def deactivate_venue_safely(venue: Venue, user, reason: str = '') -> dict:
    """
    Deactivate a venue only if it has zero future bookings.

    If any future bookings exist, raises VenueHasFutureBookings carrying the
    list — the coordinator must reassign or cancel each affected session
    before deactivation completes (SRS §3.12).
    """
    affected = find_future_bookings(venue)
    if affected:
        raise VenueHasFutureBookings(
            f'Cannot deactivate venue {venue.code}: it has {len(affected)} '
            f'future booking(s) that must be reassigned or cancelled first.',
            details={
                'venue_id': venue.id,
                'venue_code': venue.code,
                'affected_bookings': [b.to_dict() for b in affected],
            },
        )

    # Also refuse if the venue is mid-session (status == IN_USE) — that's a
    # live class, not a "future booking", and the SRS forbids silent
    # invalidation.
    if venue.status == VenueStatus.IN_USE:
        raise VenueHasFutureBookings(
            f'Cannot deactivate venue {venue.code} while a session is IN_USE. '
            f'Wait for end_time or cancel the session first.',
            details={
                'venue_id': venue.id,
                'venue_code': venue.code,
                'current_status': venue.status,
            },
        )

    venue.is_active = False
    venue.save(update_fields=['is_active', 'updated_at'])

    AuditLog.objects.create(
        user=user,
        action='VENUE_DEACTIVATED',
        entity_type='Venue',
        entity_id=str(venue.id),
        before_state={'is_active': True},
        after_state={'is_active': False},
        extra={'reason': reason, 'code': venue.code},
    )

    return {
        'venue_id': venue.id,
        'venue_code': venue.code,
        'is_active': False,
        'message': f'Venue {venue.code} deactivated.',
    }


def reactivate_venue(venue: Venue, user, reason: str = '') -> dict:
    """Re-enable a previously deactivated venue. Status stays as it was."""
    if venue.is_active:
        return {
            'venue_id': venue.id,
            'venue_code': venue.code,
            'is_active': True,
            'message': f'Venue {venue.code} is already active.',
        }

    venue.is_active = True
    venue.save(update_fields=['is_active', 'updated_at'])

    AuditLog.objects.create(
        user=user,
        action='VENUE_REACTIVATED',
        entity_type='Venue',
        entity_id=str(venue.id),
        before_state={'is_active': False},
        after_state={'is_active': True},
        extra={'reason': reason, 'code': venue.code},
    )

    return {
        'venue_id': venue.id,
        'venue_code': venue.code,
        'is_active': True,
        'message': f'Venue {venue.code} reactivated.',
    }


# ── Alternative venue finder ──────────────────────────────────────────────────

def find_alternative_venues(
    *,
    capacity_needed: int,
    venue_type: Optional[str] = None,
    required_resources: Optional[Iterable[str]] = None,
    required_accessibility: Optional[Iterable[str]] = None,
    exclude_venue_id: Optional[int] = None,
    same_building_id: Optional[int] = None,
    limit: int = 10,
) -> List[Venue]:
    """
    Return up to `limit` active, currently-FREE venues that satisfy:
      • capacity >= capacity_needed
      • venue_type matches (if given)
      • all required resources are present
      • all required accessibility features are present

    Results are ranked: same-building first, then by tightest capacity fit
    (smallest viable room).
    """
    qs = Venue.objects.filter(
        is_active=True,
        status=VenueStatus.FREE,
        capacity__gte=capacity_needed,
    ).select_related('building')

    if venue_type:
        qs = qs.filter(venue_type=venue_type)
    if exclude_venue_id:
        qs = qs.exclude(pk=exclude_venue_id)

    # Resource and accessibility filters happen in Python because JSONB
    # `contains` semantics differ subtly between Django versions; this also
    # keeps the code portable to SQLite for tests.
    required_resources = set(required_resources or [])
    required_accessibility = set(required_accessibility or [])
    if required_resources or required_accessibility:
        qs = list(qs)
        qs = [
            v for v in qs
            if v.has_resources(required_resources)
            and v.has_accessibility(required_accessibility)
        ]
    else:
        qs = list(qs)

    # Rank: same building first, then tightest capacity fit.
    def rank(v: Venue):
        same_bldg_penalty = 0 if (same_building_id and v.building_id == same_building_id) else 1
        return (same_bldg_penalty, v.capacity - capacity_needed)

    qs.sort(key=rank)
    return qs[:limit]


# ── Dashboard summary ─────────────────────────────────────────────────────────

def dashboard_summary() -> dict:
    """
    Aggregate counts for the dashboard tile / map legend.
    Counts only `is_active=True` venues.
    """
    from django.db.models import Count

    qs = Venue.objects.filter(is_active=True)
    total = qs.count()

    by_status = {s.value: 0 for s in VenueStatus}
    for row in qs.values('status').annotate(n=Count('id')):
        by_status[row['status']] = row['n']

    return {
        'total_venues': total,
        'by_status': by_status,
        'generated_at': timezone.now().isoformat(),
    }