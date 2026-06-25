"""
UTLVA Venue Recommendation Service — Phase 8

Given an expected student count and scheduling slot, returns up to 3 venues
that satisfy ALL of:
  1. capacity in [students_count, students_count × CAPACITY_OVERHEAD]
  2. venue_type matches (if specified)
  3. all required_resources present
  4. no booking overlap at (day_of_week, start_time, end_time)
  5. is_active = True

CAPACITY_OVERHEAD default: 1.5
  Example: 100 students → consider venues with capacity 100–150

Overlap rule (NEVER change): A_start < B_end AND A_end > B_start

Returns: List[dict] of up to MAX_RECOMMENDATIONS=3 venues, sorted by capacity asc.
If none found: empty list + human-readable reason string.
"""
from venues.models import Venue
from timetable.models import TimetableEntry, SystemConfiguration

MAX_RECOMMENDATIONS = 3


def _has_overlap(day_of_week, start_time, end_time, semester_id=None):
    """
    Return the set of venue IDs that are already booked at the given slot.

    Overlap rule: A_start < B_end AND A_end > B_start
    Loads DRAFT, VALIDATED, PUBLISHED entries.
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


class VenueRecommendationService:
    """
    Recommend venues for a given slot.

    Parameters
    ----------
    students_count : int
        Expected number of students.
    day_of_week : str
        e.g. 'MONDAY'
    start_time : datetime.time
    end_time : datetime.time
    venue_type : str | None
        Filter by venue type (e.g. 'LECTURE_HALL'). Optional.
    required_resources : list[str]
        Resources the venue must have (subset of venue.resources). Optional.
    semester_id : int | None
        If provided, overlap check is restricted to this semester.
    """

    def __init__(
        self,
        students_count,
        day_of_week,
        start_time,
        end_time,
        venue_type=None,
        required_resources=None,
        semester_id=None,
    ):
        self.students_count = students_count
        self.day_of_week = day_of_week
        self.start_time = start_time
        self.end_time = end_time
        self.venue_type = venue_type
        self.required_resources = required_resources or []
        self.semester_id = semester_id

    def recommend(self):
        """
        Returns dict:
        {
            "recommended": [ {...venue fields + utilization_pct + fit_label}, ... ],
            "not_found_reason": str | None,
            "capacity_range": {"min": int, "max": int},
            "students_count": int,
        }
        """
        config = SystemConfiguration.get()
        overhead = config.capacity_overhead
        cap_min = self.students_count
        cap_max = int(self.students_count * overhead)

        # Step 1: base queryset — active venues in capacity range
        qs = Venue.objects.select_related('building').filter(
            is_active=True,
            capacity__gte=cap_min,
            capacity__lte=cap_max,
        )

        # Step 2: venue type filter
        if self.venue_type:
            qs = qs.filter(venue_type=self.venue_type)

        all_candidates = list(qs.order_by('capacity'))

        # Step 3: resource filter (done in Python — resources is a JSON list)
        if self.required_resources:
            all_candidates = [
                v for v in all_candidates
                if all(r in (v.resources or []) for r in self.required_resources)
            ]

        # Step 4: availability filter — remove venues with booking overlap
        booked_ids = _has_overlap(
            self.day_of_week, self.start_time, self.end_time, self.semester_id
        )
        available = [v for v in all_candidates if v.id not in booked_ids]

        # Step 5: build reason string if nothing found
        not_found_reason = None
        if not available:
            if not all_candidates:
                # No venues even before availability check
                if self.venue_type:
                    not_found_reason = (
                        f'No active {self.venue_type} venues with capacity '
                        f'{cap_min}–{cap_max} found.'
                    )
                else:
                    not_found_reason = (
                        f'No active venues with capacity {cap_min}–{cap_max} found.'
                    )
            else:
                not_found_reason = (
                    f'All {len(all_candidates)} suitable venue(s) are already booked '
                    f'on {self.day_of_week} at this time slot.'
                )

        # Step 6: take top MAX_RECOMMENDATIONS, build response dicts
        top = available[:MAX_RECOMMENDATIONS]
        recommended = []
        for v in top:
            utilization_pct = round(self.students_count / v.capacity * 100) if v.capacity else 0
            if utilization_pct >= 90:
                fit_label = 'Best fit'
            elif utilization_pct >= 70:
                fit_label = 'Good fit'
            else:
                fit_label = 'Acceptable'

            recommended.append({
                'id': v.id,
                'code': v.code,
                'name': v.name,
                'building_name': v.building.name,
                'capacity': v.capacity,
                'venue_type': v.venue_type,
                'venue_type_display': v.get_venue_type_display(),
                'resources': v.resources or [],
                'utilization_pct': utilization_pct,
                'fit_label': fit_label,
            })

        return {
            'recommended': recommended,
            'not_found_reason': not_found_reason,
            'capacity_range': {'min': cap_min, 'max': cap_max},
            'students_count': self.students_count,
        }
