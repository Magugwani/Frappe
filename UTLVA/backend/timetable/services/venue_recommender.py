"""
UTLVA Venue Recommendation Service — SRS FR-19

Five-stage filter pipeline (SRS §3.3 Algorithm Overview):

  Stage 1 — Capacity filter
    Keep venues where expected_students ≤ venue.capacity ≤ expected_students × CAPACITY_OVERHEAD.
    The upper bound prevents allocating a 300-seat hall for a 30-student tutorial.

  Stage 2 — Time availability filter
    Reject venues with an existing booking that overlaps [start, end).
    Overlap rule (NEVER change): A.start < B.end AND A.end > B.start

  Stage 3 — Resource filter
    Venue.resources must contain every item in required_resources.
    Venue.accessibility must contain every item in required_accessibility.

  Stage 4 — Venue type filter
    If venue_type is specified, keep only matching venues.

  Stage 5 — Score and rank (SRS §3.3 Scoring)
    score = 0.7 × fit_score + 0.3 × proximity_score
    fit_score      = expected_students / venue.capacity      (1.0 when perfectly full)
    proximity_score= 1.0 if venue in same_building_id else 0.5
    Return top MAX_RECOMMENDATIONS (3) by descending score.
"""
from venues.models import Venue
from timetable.models import TimetableEntry, SystemConfiguration

MAX_RECOMMENDATIONS = 3


def _booked_venue_ids(day_of_week: str, start_time, end_time, semester_id=None) -> set:
    """
    Return IDs of venues already booked at (day_of_week, start, end).
    Overlap rule: A_start < B_end AND A_end > B_start.
    Considers DRAFT, VALIDATED, and PUBLISHED entries.
    """
    qs = TimetableEntry.objects.filter(
        day_of_week=day_of_week,
        start_time__lt=end_time,
        end_time__gt=start_time,
        status__in=['DRAFT', 'VALIDATED', 'PUBLISHED'],
        venue__isnull=False,
    )
    if semester_id is not None:
        qs = qs.filter(semester_id=semester_id)
    return set(qs.values_list('venue_id', flat=True))


def _score(venue: Venue, students_count: int, same_building_id=None) -> float:
    """
    SRS §3.3 scoring formula:
        score = 0.7 × fit_score + 0.3 × proximity_score

    fit_score      : students_count / venue.capacity (higher = tighter fit)
    proximity_score: 1.0 if same building, else 0.5
    """
    fit = students_count / venue.capacity if venue.capacity else 0.0
    prox = 1.0 if (same_building_id and venue.building_id == same_building_id) else 0.5
    return 0.7 * fit + 0.3 * prox


class VenueRecommendationService:
    """
    Parameters
    ----------
    students_count      : int      — expected attendees
    day_of_week         : str      — e.g. 'MONDAY'
    start_time          : time     — slot start
    end_time            : time     — slot end
    venue_type          : str|None — filter by VenueType
    required_resources  : list     — all must be present in venue.resources
    required_accessibility: list  — all must be present in venue.accessibility
    semester_id         : int|None — restrict availability check to this semester
    same_building_id    : int|None — building id for proximity scoring
    """

    def __init__(
        self,
        students_count: int,
        day_of_week: str,
        start_time,
        end_time,
        venue_type=None,
        required_resources=None,
        required_accessibility=None,
        semester_id=None,
        same_building_id=None,
    ):
        self.students_count       = students_count
        self.day_of_week          = day_of_week
        self.start_time           = start_time
        self.end_time             = end_time
        self.venue_type           = venue_type
        self.required_resources   = required_resources or []
        self.required_accessibility = required_accessibility or []
        self.semester_id          = semester_id
        self.same_building_id     = same_building_id

    def recommend(self) -> dict:
        """
        Returns:
        {
          "recommended": [
            {
              "id", "code", "name", "building_name", "capacity",
              "venue_type", "venue_type_display", "resources",
              "utilization_pct", "fit_label",
              "score", "fit_score", "proximity_score",
            }, ...
          ],
          "not_found_reason": str | None,
          "capacity_range": {"min": int, "max": int},
          "students_count": int,
        }
        """
        config    = SystemConfiguration.get()
        overhead  = config.capacity_overhead
        cap_min   = self.students_count
        cap_max   = int(self.students_count * overhead)

        # ── Stage 1: Capacity filter ──────────────────────────────────────────
        qs = Venue.objects.select_related('building').filter(
            is_active=True,
            capacity__gte=cap_min,
            capacity__lte=cap_max,
        )

        # ── Stage 2 (pre-screen): Venue type filter ───────────────────────────
        if self.venue_type:
            qs = qs.filter(venue_type=self.venue_type)

        candidates = list(qs)

        # ── Stage 3: Resource + accessibility filter ──────────────────────────
        if self.required_resources:
            candidates = [
                v for v in candidates
                if all(r in (v.resources or []) for r in self.required_resources)
            ]
        if self.required_accessibility:
            candidates = [
                v for v in candidates
                if all(a in (v.accessibility or []) for a in self.required_accessibility)
            ]

        # ── Stage 4: Time availability filter ─────────────────────────────────
        occupied = _booked_venue_ids(
            self.day_of_week, self.start_time, self.end_time, self.semester_id
        )
        available = [v for v in candidates if v.id not in occupied]

        # ── Build reason string if nothing survived ───────────────────────────
        not_found_reason = None
        if not available:
            if not candidates:
                type_str = f' {self.venue_type}' if self.venue_type else ''
                not_found_reason = (
                    f'No active{type_str} venues with capacity {cap_min}–{cap_max} '
                    + (f'and required resources found.' if self.required_resources else 'found.')
                )
            else:
                not_found_reason = (
                    f'All {len(candidates)} suitable venue(s) are already booked '
                    f'on {self.day_of_week} at this time slot.'
                )

        # ── Stage 5: Score and rank ───────────────────────────────────────────
        scored = sorted(
            available,
            key=lambda v: _score(v, self.students_count, self.same_building_id),
            reverse=True,  # highest score first
        )
        top = scored[:MAX_RECOMMENDATIONS]

        recommended = []
        for v in top:
            fit_s  = self.students_count / v.capacity if v.capacity else 0.0
            prox_s = 1.0 if (self.same_building_id and v.building_id == self.same_building_id) else 0.5
            total  = 0.7 * fit_s + 0.3 * prox_s

            util_pct = round(self.students_count / v.capacity * 100) if v.capacity else 0
            fit_label = 'Best fit' if util_pct >= 90 else ('Good fit' if util_pct >= 70 else 'Acceptable')

            recommended.append({
                'id': v.id,
                'code': v.code,
                'name': v.name,
                'building_name': v.building.name,
                'building_id': v.building_id,
                'floor': v.floor,
                'capacity': v.capacity,
                'venue_type': v.venue_type,
                'venue_type_display': v.get_venue_type_display(),
                'resources': v.resources or [],
                'accessibility': v.accessibility or [],
                'status': v.status,
                'utilization_pct': util_pct,
                'fit_label': fit_label,
                # SRS §3.3 scoring components (exposed for UI transparency)
                'score': round(total, 3),
                'fit_score': round(fit_s, 3),
                'proximity_score': round(prox_s, 3),
                'same_building': self.same_building_id == v.building_id if self.same_building_id else False,
            })

        return {
            'recommended': recommended,
            'not_found_reason': not_found_reason,
            'capacity_range': {'min': cap_min, 'max': cap_max},
            'students_count': self.students_count,
        }
