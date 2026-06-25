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

    # Bulk update VALIDATED → PUBLISHED
    validated_qs.update(status=TimetableStatus.PUBLISHED)

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
