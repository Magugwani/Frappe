"""
UTLVA Emergency Session Service — Phase 8

Checks lecturer/group/venue availability at the requested time before creating
the EmergencySession record.

Overlap rule (NEVER change): A_start < B_end AND A_end > B_start

Conflict flags are advisory — coordinator can approve even with conflicts.
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


class EmergencySessionService:
    """
    Check conflicts and create an EmergencySession.

    Parameters
    ----------
    course_id, lecturer_id, requested_date, day_of_week,
    start_time, end_time, reason, requested_by_user,
    venue_id (optional), student_group_ids (list, optional)
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
    ):
        self.course_id = course_id
        self.lecturer_id = lecturer_id
        self.requested_date = requested_date
        self.day_of_week = day_of_week
        self.start_time = start_time
        self.end_time = end_time
        self.reason = reason
        self.requested_by_user = requested_by_user
        self.venue_id = venue_id
        self.student_group_ids = student_group_ids or []

    def check_and_create(self):
        """
        Runs availability checks then creates and returns the EmergencySession.

        Returns EmergencySession instance (not yet related to student groups).
        Caller must handle M2M student_groups assignment.
        """
        # Check lecturer conflict
        lecturer_conflict = _slot_has_overlap(
            {'day_of_week': self.day_of_week, 'lecturer_id': self.lecturer_id},
            self.start_time,
            self.end_time,
        )

        # Check venue conflict (only if venue provided)
        venue_conflict = False
        if self.venue_id:
            venue_conflict = _slot_has_overlap(
                {'day_of_week': self.day_of_week, 'venue_id': self.venue_id},
                self.start_time,
                self.end_time,
            )

        # Check group conflicts (any of the groups)
        group_conflict = False
        for gid in self.student_group_ids:
            if _slot_has_overlap(
                {'day_of_week': self.day_of_week, 'student_group_id': gid},
                self.start_time,
                self.end_time,
            ):
                group_conflict = True
                break

        session = EmergencySession.objects.create(
            course_id=self.course_id,
            lecturer_id=self.lecturer_id,
            venue_id=self.venue_id,
            requested_date=self.requested_date,
            day_of_week=self.day_of_week,
            start_time=self.start_time,
            end_time=self.end_time,
            reason=self.reason,
            requested_by=self.requested_by_user,
            lecturer_conflict=lecturer_conflict,
            venue_conflict=venue_conflict,
            group_conflict=group_conflict,
        )

        if self.student_group_ids:
            session.student_groups.set(self.student_group_ids)

        return session

    @staticmethod
    def approve(session, reviewer_user, note=''):
        """Approve a PENDING emergency session."""
        session.status = EmergencySession.Status.APPROVED
        session.reviewed_by = reviewer_user
        session.reviewed_at = timezone.now()
        session.review_note = note
        session.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'review_note'])
        return session

    @staticmethod
    def reject(session, reviewer_user, note=''):
        """Reject a PENDING emergency session."""
        session.status = EmergencySession.Status.REJECTED
        session.reviewed_by = reviewer_user
        session.reviewed_at = timezone.now()
        session.review_note = note
        session.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'review_note'])
        return session
