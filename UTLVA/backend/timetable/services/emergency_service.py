"""
UTLVA Emergency Session Service — SRS §3.7

Checks lecturer/group/venue availability at the requested time before creating
the EmergencySession record.

Overlap rule (NEVER change): A_start < B_end AND A_end > B_start

Conflict flags are advisory — coordinator can approve even with conflicts.

SRS §3.7 additions:
  - After creation  → notify all Coordinators (in-app) of pending request
  - After approval  → transition venue FREE→BOOKED, notify requesting lecturer
  - After rejection → notify requesting lecturer
"""
from django.utils import timezone
from timetable.models import TimetableEntry, EmergencySession


def _slot_has_overlap(qs_filter, start_time, end_time):
    """Return True if any entry in the queryset overlaps the given slot."""
    return TimetableEntry.objects.filter(
        **qs_filter,
        start_time__lt=end_time,
        end_time__gt=start_time,
        status__in=['DRAFT', 'VALIDATED', 'PUBLISHED'],
    ).exists()


def _notify_coordinators(session, created_by_user):
    """Create an in-app notification for every active Coordinator."""
    try:
        from notifications.models import Notification
        from accounts.models import Role
        course_code = session.course.course_code
        title = session.title or course_code
        Notification.broadcast_to_role(
            role=Role.COORDINATOR,
            notification_type=Notification.Type.EMERGENCY_CREATED,
            title=f'Emergency Session Request: {title}',
            body=(
                f'{created_by_user.full_name} has requested an emergency session.\n'
                f'Course: {course_code}\n'
                f'Date: {session.requested_date}  {session.day_of_week}  '
                f'{session.start_time:%H:%M}–{session.end_time:%H:%M}\n'
                f'Reason: {session.reason}'
            ),
            sender=created_by_user,
            related_object_type='EmergencySession',
            related_object_id=session.pk,
        )
    except Exception:
        pass  # non-critical — session is created regardless


def _notify_lecturer_approved(session, reviewer_user):
    """Notify the requesting lecturer that the session was approved."""
    try:
        from notifications.models import Notification
        Notification.create_for_user(
            recipient=session.requested_by,
            notification_type=Notification.Type.EMERGENCY_APPROVED,
            title=f'Your Emergency Session Confirmed ✓',
            body=(
                f'Your emergency session for {session.course.course_code} has been '
                f'approved by {reviewer_user.full_name}.\n'
                f'Date: {session.requested_date}  {session.day_of_week}  '
                f'{session.start_time:%H:%M}–{session.end_time:%H:%M}\n'
                f'Venue: {session.venue.code if session.venue else "TBA"}\n'
                f'Note: {session.review_note or "—"}'
            ),
            sender=reviewer_user,
            related_object_type='EmergencySession',
            related_object_id=session.pk,
        )
    except Exception:
        pass


def _notify_lecturer_rejected(session, reviewer_user):
    """Notify the requesting lecturer that the session was rejected."""
    try:
        from notifications.models import Notification
        Notification.create_for_user(
            recipient=session.requested_by,
            notification_type=Notification.Type.EMERGENCY_REJECTED,
            title=f'Emergency Session Rejected',
            body=(
                f'Your emergency session request for {session.course.course_code} has been '
                f'rejected by {reviewer_user.full_name}.\n'
                f'Reason: {session.review_note or "No reason provided."}'
            ),
            sender=reviewer_user,
            related_object_type='EmergencySession',
            related_object_id=session.pk,
        )
    except Exception:
        pass


def _set_venue_booked(session, reviewer_user):
    """
    Transition the session's venue FREE → BOOKED using the VenueStateMachine.
    Records start/end time in the history reason field.
    """
    if not session.venue_id:
        return
    try:
        from venues.models import VenueStatus, TransitionEvent, Venue
        from venues.services import VenueStateMachine
        venue = Venue.objects.get(pk=session.venue_id)
        if venue.status != VenueStatus.FREE:
            return  # already booked or in another state
        machine = VenueStateMachine(venue)
        machine.transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.SESSION_CREATED,
            user=reviewer_user,
            reason=(
                f'Emergency session approved. {session.course.course_code}  '
                f'{session.requested_date}  '
                f'{session.start_time:%H:%M}–{session.end_time:%H:%M}.'
            ),
            related_object_type='EmergencySession',
            related_object_id=str(session.pk),
        )
    except Exception:
        pass  # non-critical — approval proceeds regardless


class EmergencySessionService:
    """
    FR-23/24: Check all conflicts then create an EmergencySession.

    Conflicts are advisory — a coordinator can approve even when flags are set.
    """

    def __init__(
        self,
        course_id,
        lecturer_id,
        requested_date,
        day_of_week,
        start_time,
        end_time,
        reason,
        requested_by_user,
        venue_id=None,
        student_group_ids=None,
        # FR-23 new optional fields
        title='',
        expected_students=None,
        required_resources=None,
        comments='',
    ):
        self.course_id          = course_id
        self.lecturer_id        = lecturer_id
        self.requested_date     = requested_date
        self.day_of_week        = day_of_week
        self.start_time         = start_time
        self.end_time           = end_time
        self.reason             = reason
        self.requested_by_user  = requested_by_user
        self.venue_id           = venue_id
        self.student_group_ids  = student_group_ids or []
        self.title              = title or ''
        self.expected_students  = expected_students
        self.required_resources = required_resources or []
        self.comments           = comments or ''

    def check_and_create(self):
        """
        Run FR-24 validation checks, create and return the EmergencySession.
        M2M student_groups assignment is handled here.
        After creation, notify all Coordinators in-app (FR-45).
        """
        # FR-24a: Lecturer availability
        lecturer_conflict = _slot_has_overlap(
            {'day_of_week': self.day_of_week, 'lecturer_id': self.lecturer_id},
            self.start_time, self.end_time,
        )

        # FR-24b: Venue availability
        venue_conflict = False
        if self.venue_id:
            venue_conflict = _slot_has_overlap(
                {'day_of_week': self.day_of_week, 'venue_id': self.venue_id},
                self.start_time, self.end_time,
            )

        # FR-24c: Student group conflicts
        group_conflict = False
        for gid in self.student_group_ids:
            if _slot_has_overlap(
                {'day_of_week': self.day_of_week, 'student_group_id': gid},
                self.start_time, self.end_time,
            ):
                group_conflict = True
                break

        # FR-24d: Capacity check
        capacity_conflict = False
        if self.venue_id and self.expected_students:
            from venues.models import Venue
            try:
                venue = Venue.objects.get(pk=self.venue_id)
                capacity_conflict = venue.capacity < self.expected_students
            except Venue.DoesNotExist:
                pass

        session = EmergencySession.objects.create(
            title=self.title,
            course_id=self.course_id,
            lecturer_id=self.lecturer_id,
            expected_students=self.expected_students,
            required_resources=self.required_resources,
            venue_id=self.venue_id,
            requested_date=self.requested_date,
            day_of_week=self.day_of_week,
            start_time=self.start_time,
            end_time=self.end_time,
            reason=self.reason,
            comments=self.comments,
            requested_by=self.requested_by_user,
            lecturer_conflict=lecturer_conflict,
            venue_conflict=venue_conflict,
            group_conflict=group_conflict,
            capacity_conflict=capacity_conflict,
        )

        if self.student_group_ids:
            session.student_groups.set(self.student_group_ids)

        # FR-45 / SRS §3.7 — notify coordinators of new pending request
        _notify_coordinators(session, self.requested_by_user)

        return session

    @staticmethod
    def approve(session, reviewer_user, note=''):
        """
        Approve a PENDING emergency session.
        - Saves APPROVED status with reviewer info
        - Transitions venue FREE → BOOKED (FR-47 prerequisite)
        - Creates in-app notification for the requesting lecturer (FR-45)
        """
        session.status = EmergencySession.Status.APPROVED
        session.reviewed_by = reviewer_user
        session.reviewed_at = timezone.now()
        session.review_note = note
        session.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'review_note'])

        # Wire venue to BOOKED (SRS §3.7 NOTE point i)
        _set_venue_booked(session, reviewer_user)

        # Notify lecturer (SRS §3.7 NOTE point ii-a)
        _notify_lecturer_approved(session, reviewer_user)

        return session

    @staticmethod
    def reject(session, reviewer_user, note=''):
        """
        Reject a PENDING emergency session.
        Creates in-app notification for the requesting lecturer (FR-45).
        """
        session.status = EmergencySession.Status.REJECTED
        session.reviewed_by = reviewer_user
        session.reviewed_at = timezone.now()
        session.review_note = note
        session.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'review_note'])

        # Notify lecturer (SRS §3.7 NOTE point ii-b)
        _notify_lecturer_rejected(session, reviewer_user)

        return session
