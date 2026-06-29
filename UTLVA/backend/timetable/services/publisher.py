"""
UTLVA Timetable Publishing Service — Phase 7

Lifecycle
---------
DRAFT → VALIDATED → PUBLISHED

Rules
-----
1. Publishing is only allowed when:
   a. At least one VALIDATED entry exists for the semester.
   b. Zero OPEN conflicts exist for the semester.

2. Unpublishing (PUBLISHED → VALIDATED) is reserved for SYSTEM_ADMIN only.

3. Each successful publish creates a TimetablePublication audit record.

4. Conflicts can be manually resolved by Coordinator/Admin with a resolution note.
   Resolving a conflict does NOT automatically re-validate — coordinator must
   re-run validation to promote entries back to VALIDATED.
"""

from django.utils import timezone
from timetable.models import TimetableEntry, TimetableConflict, TimetablePublication, TimetableStatus
from accounts.models import Role


# ── Venue status helpers (SRS 3.2 integration) ───────────────────────────────

def _set_venues_booked(entries: list, user) -> None:
    """
    After publishing, transition every referenced venue FREE → BOOKED.
    Venues already BOOKED/IN_USE are left unchanged (another session is using them).
    Transition failures never block publishing — they are silent.
    """
    from venues.services import VenueStateMachine, IllegalTransition, TransitionRequiresForce
    from venues.models import VenueStatus, TransitionEvent

    seen_venue_ids: set = set()
    for entry in entries:
        if not entry.venue_id or entry.venue_id in seen_venue_ids:
            continue
        seen_venue_ids.add(entry.venue_id)
        venue = entry.venue
        if not venue.is_active:
            continue
        if venue.status != VenueStatus.FREE:
            continue
        try:
            VenueStateMachine(venue).transition(
                to_status=VenueStatus.BOOKED,
                event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
                user=user,
                reason=f'Timetable published — {entry.course.course_code} assigned to this venue.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
            )
        except (IllegalTransition, TransitionRequiresForce, Exception):
            pass   # venue state transition failure must never block publishing


def _release_venues_to_free(semester, user) -> None:
    """
    When unpublishing, transition every venue referenced in this semester's
    published entries back to FREE — unless another semester is still using them.
    """
    from venues.services import VenueStateMachine
    from venues.models import VenueStatus, TransitionEvent

    published_entries = TimetableEntry.objects.filter(
        semester=semester,
        status=TimetableStatus.PUBLISHED,
        venue__isnull=False,
    ).select_related('venue')

    for entry in published_entries:
        venue = entry.venue
        if not venue or not venue.is_active:
            continue
        if venue.status not in (VenueStatus.BOOKED, VenueStatus.IN_USE):
            continue
        try:
            VenueStateMachine(venue).transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.SESSION_CANCELLED,
                user=user,
                reason='Timetable unpublished — venue released.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
                force=True,  # allow FREE even from IN_USE if admin unpublishes
            )
        except Exception:
            pass


# ── Status ────────────────────────────────────────────────────────────────────

def get_timetable_status(academic_year, semester) -> dict:
    """
    Returns the current lifecycle state of the timetable for a semester.

    Determines dominant status by priority:
      PUBLISHED  → any entry is published
      VALIDATED  → at least one validated, none published
      DRAFT      → entries exist but none validated or published
      EMPTY      → no entries at all
    """
    entries = TimetableEntry.objects.filter(semester=semester)
    open_conflicts = TimetableConflict.objects.filter(
        timetable_entry_a__semester=semester,
        status=TimetableConflict.Status.OPEN,
    ).count()
    resolved_conflicts = TimetableConflict.objects.filter(
        timetable_entry_a__semester=semester,
        status=TimetableConflict.Status.RESOLVED,
    ).count()

    counts = {
        'total': entries.count(),
        'draft': entries.filter(status=TimetableStatus.DRAFT).count(),
        'validated': entries.filter(status=TimetableStatus.VALIDATED).count(),
        'published': entries.filter(status=TimetableStatus.PUBLISHED).count(),
        'archived': entries.filter(status=TimetableStatus.ARCHIVED).count(),
    }

    if counts['total'] == 0:
        dominant = 'EMPTY'
    elif counts['published'] > 0:
        dominant = 'PUBLISHED'
    elif counts['validated'] > 0:
        dominant = 'VALIDATED'
    else:
        dominant = 'DRAFT'

    last_pub = TimetablePublication.objects.filter(
        semester=semester, status='ACTIVE'
    ).first()

    return {
        'dominant_status': dominant,
        'entry_counts': counts,
        'open_conflicts': open_conflicts,
        'resolved_conflicts': resolved_conflicts,
        'can_publish': dominant == 'VALIDATED' and open_conflicts == 0,
        'can_validate': dominant in ('DRAFT', 'EMPTY') or counts['draft'] > 0,
        'last_publication': {
            'id': last_pub.id,
            'published_by': last_pub.published_by.full_name if last_pub and last_pub.published_by else None,
            'published_at': str(last_pub.published_at) if last_pub else None,
            'entries': last_pub.published_entries_count if last_pub else 0,
        } if last_pub else None,
        'academic_year': academic_year.name,
        'semester': semester.name,
    }


# ── Publish ───────────────────────────────────────────────────────────────────

def publish_timetable(academic_year, semester, user) -> dict:
    """
    Promote all VALIDATED entries → PUBLISHED.

    Preconditions:
      1. Zero OPEN conflicts.
      2. At least one VALIDATED entry.

    On success:
      - Updates entries in bulk.
      - Marks previous active publications as SUPERSEDED.
      - Creates new TimetablePublication record.
    """
    open_conflicts = TimetableConflict.objects.filter(
        timetable_entry_a__semester=semester,
        status=TimetableConflict.Status.OPEN,
    ).count()

    if open_conflicts > 0:
        return {
            'success': False,
            'status': 'FAILED',
            'message': (
                f'Cannot publish. {open_conflicts} open conflict(s) must be '
                f'resolved before publishing. Use the Conflict Resolution screen '
                f'to resolve them, then re-validate.'
            ),
            'open_conflicts': open_conflicts,
        }

    validated_qs = TimetableEntry.objects.filter(
        semester=semester,
        status=TimetableStatus.VALIDATED,
    )
    if not validated_qs.exists():
        return {
            'success': False,
            'status': 'FAILED',
            'message': (
                'Cannot publish. No validated timetable entries found. '
                'Run validation first to promote DRAFT entries to VALIDATED.'
            ),
            'open_conflicts': 0,
        }

    count = validated_qs.count()

    # Snapshot the entries that will be published (need venues BEFORE bulk update)
    publishing_entries = list(
        validated_qs.select_related('venue', 'course').filter(venue__isnull=False)
    )

    # Bulk update VALIDATED → PUBLISHED
    validated_qs.update(status=TimetableStatus.PUBLISHED)

    # ── SRS 3.2: Venue status → BOOKED when timetable is published ────────────
    # Every venue referenced by a newly-published entry transitions FREE → BOOKED.
    # This is the authoritative trigger for the venue status machine.
    _set_venues_booked(publishing_entries, user)

    # Mark previous active publications as superseded
    TimetablePublication.objects.filter(
        semester=semester,
        status=TimetablePublication.PubStatus.ACTIVE,
    ).update(status=TimetablePublication.PubStatus.SUPERSEDED)

    # Create publication audit record
    pub = TimetablePublication.objects.create(
        academic_year=academic_year,
        semester=semester,
        published_by=user,
        published_entries_count=count,
    )

    return {
        'success': True,
        'status': 'PUBLISHED',
        'message': f'Timetable published successfully. {count} entries are now live.',
        'published_entries': count,
        'publication_id': pub.id,
        'published_at': str(pub.published_at),
    }


# ── Unpublish (SYSTEM_ADMIN only) ─────────────────────────────────────────────

def unpublish_timetable(semester, user) -> dict:
    """
    Revert PUBLISHED → VALIDATED.
    Only SYSTEM_ADMIN may do this.
    """
    if user.role != Role.SYSTEM_ADMIN:
        return {
            'success': False,
            'message': 'Only System Administrators can unpublish a timetable.',
        }

    published_qs = TimetableEntry.objects.filter(
        semester=semester,
        status=TimetableStatus.PUBLISHED,
    )
    if not published_qs.exists():
        return {
            'success': False,
            'message': 'No published entries found for this semester.',
        }

    count = published_qs.count()

    # SRS 3.2: release venues before reverting entry status
    _release_venues_to_free(semester, user)

    published_qs.update(status=TimetableStatus.VALIDATED)

    TimetablePublication.objects.filter(
        semester=semester,
        status=TimetablePublication.PubStatus.ACTIVE,
    ).update(status=TimetablePublication.PubStatus.SUPERSEDED)

    return {
        'success': True,
        'message': f'Timetable unpublished. {count} entries reverted to VALIDATED.',
        'reverted_entries': count,
    }


# ── Conflict resolution ───────────────────────────────────────────────────────

def resolve_conflict(conflict_id, user, resolution_note: str) -> dict:
    """
    Mark a TimetableConflict as RESOLVED.

    After resolving, entries involved are NOT automatically re-validated.
    The coordinator must re-run validation to promote them if appropriate.
    """
    try:
        conflict = TimetableConflict.objects.get(pk=conflict_id)
    except TimetableConflict.DoesNotExist:
        return {'success': False, 'message': 'Conflict not found.'}

    if conflict.status == TimetableConflict.Status.RESOLVED:
        return {'success': False, 'message': 'Conflict is already resolved.'}

    conflict.status = TimetableConflict.Status.RESOLVED
    conflict.resolved_by = user
    conflict.resolved_at = timezone.now()
    conflict.resolution_note = resolution_note.strip()
    conflict.save(update_fields=['status', 'resolved_by', 'resolved_at', 'resolution_note'])

    return {
        'success': True,
        'conflict_id': conflict.id,
        'resolved_at': str(conflict.resolved_at),
        'message': 'Conflict marked as resolved.',
    }


# ── Session lifecycle (SRS 3.2 — FR-29, FR-30, FR-33, FR-34) ─────────────────

def cancel_session(entry_id: int, cancelling_user, urgent: bool = False) -> dict:
    """
    Cancel a session — supports both pre-start (BOOKED) and mid-session (IN_USE).

    SRS §3.12: If the venue is IN_USE (session already started), the lecturer
    may cancel the REMAINDER of the session.  The venue transitions IN_USE → FREE
    and students receive an urgent-tier notification.

    Cancellation rules:
    - Entry must be PUBLISHED (or IN_USE if called from within the window).
    - Venue may be BOOKED or IN_USE.
    - Coordinator or Admin can cancel any session; a lecturer can only cancel their own.
    """
    from venues.services import VenueStateMachine
    from venues.models import VenueStatus, TransitionEvent
    from accounts.models import Role

    try:
        entry = TimetableEntry.objects.select_related(
            'venue', 'course', 'lecturer__user'
        ).get(pk=entry_id)
    except TimetableEntry.DoesNotExist:
        return {'success': False, 'message': 'Timetable entry not found.'}

    if entry.status != TimetableStatus.PUBLISHED:
        return {'success': False, 'message': 'Only PUBLISHED sessions can be cancelled.'}

    # Lecturers can only cancel their own sessions
    if cancelling_user.role == Role.LECTURER:
        if entry.lecturer.user_id != cancelling_user.id:
            return {'success': False, 'message': 'You can only cancel sessions you are assigned to teach.'}

    # Release venue — supports both BOOKED and IN_USE (SRS §3.12)
    if entry.venue and entry.venue.status in (VenueStatus.BOOKED, VenueStatus.IN_USE):
        in_use = entry.venue.status == VenueStatus.IN_USE
        try:
            VenueStateMachine(entry.venue).transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.SESSION_CANCELLED,
                user=cancelling_user,
                reason=(
                    f'{"Mid-session cancellation" if in_use else "Session cancelled"} '
                    f'by {cancelling_user.full_name}: '
                    f'{entry.course.course_code} {entry.day_of_week} '
                    f'{entry.start_time:%H:%M}–{entry.end_time:%H:%M}.'
                ),
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
                force=in_use,  # IN_USE → FREE requires force flag
            )
        except Exception:
            pass

    entry.status = TimetableStatus.DRAFT
    entry.save(update_fields=['status'])

    cancel_reason = f'{"[URGENT] " if urgent else ""}Cancelled by {cancelling_user.full_name}.'
    _notify_cancellation_email(entry, reason=cancel_reason)

    return {
        'success': True,
        'message': (
            f'Session cancelled. {entry.course.course_code} on {entry.day_of_week} '
            f'{entry.start_time:%H:%M}–{entry.end_time:%H:%M} moved back to DRAFT.'
        ),
    }


def confirm_session(entry_id: int, lecturer_user, session_date=None) -> dict:
    """
    Lecturer confirms a session is starting (FR-29, FR-33).

    SRS §3.12 — Concurrent confirmation safety:
      Uses select_for_update() to serialize concurrent requests from the
      same lecturer on two devices. The second identical request returns
      success (idempotent) if already confirmed by this lecturer today.
      If the venue is IN_USE by a DIFFERENT confirmation, returns CONFLICT.

    SRS §3.12 — Network-loss retry:
      The `session_date` parameter carries the original_timestamp from the
      offline-retry queue. If the original confirmation time was within the
      window but arrival is late, the view layer must check the window.
    """
    from django.db import transaction
    from venues.services import VenueStateMachine
    from venues.models import VenueStatus, TransitionEvent
    from timetable.models import SessionConfirmation

    today = session_date or timezone.localdate()

    with transaction.atomic():
        try:
            # select_for_update prevents two concurrent confirmations racing
            entry = TimetableEntry.objects.select_related(
                'venue', 'course', 'lecturer__user', 'student_group',
            ).select_for_update().get(pk=entry_id)
        except TimetableEntry.DoesNotExist:
            return {'success': False, 'message': 'Timetable entry not found.'}

        if entry.status != TimetableStatus.PUBLISHED:
            return {'success': False, 'message': 'Only PUBLISHED sessions can be confirmed.'}

        if entry.lecturer.user_id != lecturer_user.id:
            return {'success': False, 'message': 'You can only confirm sessions you are assigned to teach.'}

        if not entry.venue:
            return {'success': False, 'message': 'This entry has no venue assigned.'}

        venue = entry.venue

        # ── SRS §3.12: Idempotency — already confirmed by this lecturer today ─
        existing = SessionConfirmation.objects.filter(
            timetable_entry=entry,
            session_date=today,
            status=SessionConfirmation.Status.CONFIRMED,
        ).first()
        if existing:
            # Already confirmed — return success, not an error
            return {
                'success': True,
                'already_confirmed': True,
                'message': f'Session {entry.course.course_code} is already confirmed for today.',
                'venue_status': venue.status,
                'confirmed_at': existing.confirmed_at.isoformat() if existing.confirmed_at else None,
                'session_date': str(today),
            }

        # ── SRS §3.12: CONFLICT — venue IN_USE by another session ─────────────
        if venue.status == VenueStatus.IN_USE:
            return {
                'success': False,
                'error_code': 'CONFLICT',
                'message': (
                    f'Venue {venue.code} is already IN_USE — it appears another '
                    f'confirmation reached the server first. Your session may already '
                    f'be confirmed.'
                ),
            }

        if venue.status not in (VenueStatus.BOOKED, VenueStatus.FREE):
            return {'success': False, 'message': f'Venue is {venue.status} — cannot confirm.'}

        # ── FR-33: Change venue status to IN_USE ───────────────────────────────
        try:
            VenueStateMachine(venue).transition(
                to_status=VenueStatus.IN_USE,
                event=TransitionEvent.LECTURER_CONFIRMED,
                user=lecturer_user,
                reason=f'{lecturer_user.full_name} confirmed session: {entry.course.course_code}.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
                force=(venue.status != VenueStatus.BOOKED),
            )
        except Exception as exc:
            return {'success': False, 'message': f'Venue transition failed: {exc}'}

        # ── FR-33: Record confirmation ─────────────────────────────────────────
        confirmation, _ = SessionConfirmation.objects.update_or_create(
            timetable_entry=entry,
            session_date=today,
            defaults={
                'status': SessionConfirmation.Status.CONFIRMED,
                'confirmed_at': timezone.now(),
                'confirmed_by': lecturer_user,
            },
        )

    # ── FR-33: Notify students (outside transaction — non-critical) ────────────
    _notify_confirm_email(entry, confirmation)

    return {
        'success': True,
        'already_confirmed': False,
        'message': f'Session confirmed. Venue {venue.code} is now IN_USE.',
        'venue_status': VenueStatus.IN_USE,
        'confirmed_at': confirmation.confirmed_at.isoformat(),
        'session_date': str(today),
    }


def end_session(entry_id: int, user) -> dict:
    """
    Mark session as ended — venue IN_USE → FREE.
    Called by lecturer after class or automatically by Celery at end_time.
    """
    from venues.services import VenueStateMachine
    from venues.models import VenueStatus, TransitionEvent

    try:
        entry = TimetableEntry.objects.select_related('venue', 'course').get(pk=entry_id)
    except TimetableEntry.DoesNotExist:
        return {'success': False, 'message': 'Timetable entry not found.'}

    if not entry.venue:
        return {'success': False, 'message': 'No venue assigned to this entry.'}

    venue = entry.venue
    if venue.status not in (VenueStatus.IN_USE, VenueStatus.BOOKED):
        return {'success': False, 'message': f'Venue is {venue.status} — nothing to release.'}

    try:
        VenueStateMachine(venue).transition(
            to_status=VenueStatus.FREE,
            event=TransitionEvent.SESSION_ENDED,
            user=user,
            reason=f'Session ended: {entry.course.course_code}.',
            related_object_type='TimetableEntry',
            related_object_id=str(entry.id),
            force=True,
        )
    except Exception as exc:
        return {'success': False, 'message': f'Venue release failed: {exc}'}

    return {
        'success': True,
        'message': f'Session ended. Venue {venue.code} is now FREE.',
        'venue_status': VenueStatus.FREE,
    }


# ── Session postponement (FR-26, FR-27) ──────────────────────────────────────

def postpone_session(entry_id: int, postpone_data: dict, requesting_user) -> dict:
    """
    Postpone one occurrence of a published TimetableEntry to a new date/time/venue.

    Steps:
      1. Validate: entry is PUBLISHED; user is the assigned lecturer, coordinator, or admin.
      2. Create a SessionPostponement record.
      3. If original venue is BOOKED → transition FREE (SESSION_CANCELLED).
      4. If new_venue provided and FREE → transition BOOKED (TIMETABLE_ENTRY_CREATED).
      5. Send email notification to enrolled students (FR-28).
    """
    from timetable.models import TimetableEntry, TimetableStatus, SessionPostponement
    from venues.services import VenueStateMachine
    from venues.models import VenueStatus, TransitionEvent
    from accounts.models import Role

    try:
        entry = TimetableEntry.objects.select_related(
            'venue', 'course', 'lecturer__user', 'programme', 'student_group'
        ).get(pk=entry_id)
    except TimetableEntry.DoesNotExist:
        return {'success': False, 'message': 'Timetable entry not found.'}

    if entry.status != TimetableStatus.PUBLISHED:
        return {'success': False, 'message': 'Only PUBLISHED sessions can be postponed.'}

    # SRS §3.12: Reject postponement of an in-progress session
    if entry.venue and entry.venue.status == VenueStatus.IN_USE:
        return {
            'success': False,
            'error_code': 'SESSION_ALREADY_STARTED',
            'message': (
                f'Cannot postpone {entry.course.course_code}: the session is already '
                f'IN PROGRESS (venue {entry.venue.code} is IN_USE). '
                f'You may cancel the remainder of the session instead.'
            ),
        }

    # Lecturers can only postpone their own sessions
    if requesting_user.role == Role.LECTURER:
        if entry.lecturer.user_id != requesting_user.id:
            return {'success': False, 'message': 'You can only postpone sessions you are assigned to teach.'}

    new_venue = postpone_data.get('new_venue')

    # Create postponement record
    postponement = SessionPostponement.objects.create(
        original_entry=entry,
        new_date=postpone_data['new_date'],
        new_day_of_week=postpone_data['new_day_of_week'],
        new_start_time=postpone_data['new_start_time'],
        new_end_time=postpone_data['new_end_time'],
        new_venue=new_venue,
        reason=postpone_data['reason'],
        postponed_by=requesting_user,
    )

    # Release original venue
    if entry.venue and entry.venue.status == VenueStatus.BOOKED:
        try:
            VenueStateMachine(entry.venue).transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.SESSION_CANCELLED,
                user=requesting_user,
                reason=f'Session postponed by {requesting_user.full_name}. Reason: {postpone_data["reason"]}',
                related_object_type='SessionPostponement',
                related_object_id=str(postponement.id),
            )
        except Exception:
            pass

    # Book new venue if provided and available
    if new_venue and new_venue.status == VenueStatus.FREE:
        try:
            VenueStateMachine(new_venue).transition(
                to_status=VenueStatus.BOOKED,
                event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
                user=requesting_user,
                reason=f'Postponed session from {entry.course.course_code} {entry.day_of_week}.',
                related_object_type='SessionPostponement',
                related_object_id=str(postponement.id),
            )
        except Exception:
            pass

    # FR-28: email notification to enrolled students
    _notify_postponement_email(entry, postponement)

    return {
        'success': True,
        'message': (
            f'{entry.course.course_code} session postponed from '
            f'{entry.day_of_week} {entry.start_time:%H:%M} to '
            f'{postponement.new_date} {postponement.new_start_time:%H:%M}.'
        ),
        'postponement_id': postponement.id,
        'new_date': str(postponement.new_date),
        'new_day_of_week': postponement.new_day_of_week,
        'new_start_time': str(postponement.new_start_time),
        'new_end_time': str(postponement.new_end_time),
        'new_venue_code': new_venue.code if new_venue else None,
    }


# ── FR-28/49: Multi-channel notifications via dispatcher ──────────────────────

def _students_for_entry(entry) -> list:
    """Return User objects for students enrolled in the entry's student group."""
    from academics.models import StudentProfile
    group = entry.student_group
    if not group:
        return []
    return list(
        StudentProfile.objects.filter(student_group=group)
        .select_related('user')
        .values_list('user', flat=False)
        .values_list('user_id', flat=True)
    )


def _student_users_for_entry(entry) -> list:
    """Return User queryset for students enrolled in entry's student group."""
    from accounts.models import User
    from academics.models import StudentProfile
    group = entry.student_group
    if not group:
        return []
    user_ids = StudentProfile.objects.filter(
        student_group=group
    ).values_list('user_id', flat=True)
    return list(User.objects.filter(pk__in=user_ids, is_active=True))


def _notify_confirm_email(entry, confirmation) -> None:
    """
    FR-33/49: Notify enrolled students that the session is confirmed.
    Routes through NotificationDispatcher (in-app + email + push + SMS).
    """
    try:
        from notifications.dispatcher import dispatch
        from notifications.models import Notification

        recipients = _student_users_for_entry(entry)
        if not recipients:
            return

        venue_text = (
            f'{entry.venue.code} — {entry.venue.name}, {entry.venue.building.name}, Floor {entry.venue.floor}'
            if entry.venue else 'TBA'
        )
        confirmed_by = confirmation.confirmed_by.full_name if confirmation.confirmed_by else 'Lecturer'
        body = (
            f'Your {entry.course.course_name} session is confirmed and IN PROGRESS.\n'
            f'Day: {entry.day_of_week} {entry.start_time:%H:%M}–{entry.end_time:%H:%M}\n'
            f'Venue: {venue_text}\n'
            f'Confirmed by: {confirmed_by}'
        )
        dispatch(
            event_id=f'confirm:{entry.pk}:{confirmation.session_date}',
            recipients=recipients,
            notification_type=Notification.Type.SESSION_CONFIRMED,
            title=f'Session Confirmed — {entry.course.course_code}',
            body=body,
            sender=confirmation.confirmed_by,
            related_object_type='TimetableEntry',
            related_object_id=entry.pk,
            sms_message=f'UTLVA: {entry.course.course_code} confirmed at {venue_text}. {entry.start_time:%H:%M}',
        )
    except Exception:
        pass


def _notify_postponement_email(entry, postponement) -> None:
    """FR-28/49: Multi-channel postponement notification."""
    try:
        from notifications.dispatcher import dispatch
        from notifications.models import Notification

        recipients = _student_users_for_entry(entry)
        if not recipients:
            return

        new_venue_text = (
            f' New venue: {postponement.new_venue.code} — {postponement.new_venue.name}.'
            if postponement.new_venue else ''
        )
        body = (
            f'Your {entry.course.course_name} session has been postponed.\n'
            f'Original: {entry.day_of_week} {entry.start_time:%H:%M}–{entry.end_time:%H:%M}\n'
            f'New: {postponement.new_date} ({postponement.new_day_of_week}) '
            f'{postponement.new_start_time:%H:%M}–{postponement.new_end_time:%H:%M}'
            f'{new_venue_text}\n'
            f'Reason: {postponement.reason}'
        )
        dispatch(
            event_id=f'postpone:{entry.pk}:{postponement.pk}',
            recipients=recipients,
            notification_type=Notification.Type.SESSION_POSTPONED,
            title=f'Session Postponed — {entry.course.course_code}',
            body=body,
            sender=postponement.postponed_by,
            related_object_type='SessionPostponement',
            related_object_id=postponement.pk,
            sms_message=(
                f'UTLVA: {entry.course.course_code} moved to '
                f'{postponement.new_date} {postponement.new_start_time:%H:%M}.'
                f'{new_venue_text}'
            ),
        )
    except Exception:
        pass


def _notify_cancellation_email(entry, reason: str = '') -> None:
    """FR-28/49: Multi-channel cancellation notification."""
    try:
        from notifications.dispatcher import dispatch
        from notifications.models import Notification

        recipients = _student_users_for_entry(entry)
        if not recipients:
            return

        body = (
            f'The {entry.course.course_name} session on {entry.day_of_week} '
            f'{entry.start_time:%H:%M}–{entry.end_time:%H:%M} has been CANCELLED.\n'
            + (f'Reason: {reason}' if reason else '')
        )
        dispatch(
            event_id=f'cancel:{entry.pk}',
            recipients=recipients,
            notification_type=Notification.Type.SESSION_CANCELLED,
            title=f'Session Cancelled — {entry.course.course_code}',
            body=body,
            related_object_type='TimetableEntry',
            related_object_id=entry.pk,
            sms_message=f'UTLVA: {entry.course.course_code} session CANCELLED. {reason}',
        )
    except Exception:
        pass
