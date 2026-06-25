"""
UTLVA — Venue module tests.

Run:
    python manage.py test venues -v 2

Covers the SRS §3.3 contract:
  • Legal transitions write history and update the venue.
  • Illegal transitions are rejected with the right error code.
  • Composite BOOKED → EXPIRED → FREE writes two history rows and ends FREE.
  • Deactivation with future bookings is refused with the affected list.
  • Search filters by resource and accessibility actually narrow the result set.
  • Dashboard projection returns the expected shape.
"""

from datetime import time, date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import Role
from .models import (
    Building, Venue, VenueStatus, VenueStatusHistory,
    VenueType, TransitionEvent,
)
from .services import (
    VenueStateMachine,
    IllegalTransition,
    TransitionRequiresForce,
    VenueHasFutureBookings,
    deactivate_venue_safely,
    find_alternative_venues,
)

User = get_user_model()


def _make_user(email='admin@utlva.local', role=Role.SYSTEM_ADMIN):
    return User.objects.create_user(
        email=email, password='Pass123!@#', full_name='Admin User', role=role,
    )


def _make_building(code='COICT', name='College of ICT'):
    return Building.objects.create(
        code=code, name=name,
        latitude=Decimal('-6.769320'), longitude=Decimal('39.230110'),
    )


def _make_venue(building, code='COICT-LH1', capacity=100,
                 venue_type=VenueType.LECTURE_HALL,
                 resources=None, accessibility=None,
                 status_=VenueStatus.FREE):
    return Venue.objects.create(
        code=code, name=f'Venue {code}', building=building,
        floor=0, capacity=capacity, venue_type=venue_type,
        resources=resources or [],
        accessibility=accessibility or [],
        status=status_, is_active=True,
    )


# ── State machine ─────────────────────────────────────────────────────────────

class VenueStateMachineTests(APITestCase):
    def setUp(self):
        self.admin = _make_user()
        self.building = _make_building()
        self.venue = _make_venue(self.building)

    def test_free_to_booked_writes_history(self):
        result = VenueStateMachine(self.venue).transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
            user=self.admin,
        )
        self.venue.refresh_from_db()
        self.assertEqual(self.venue.status, VenueStatus.BOOKED)
        self.assertEqual(result.previous_status, VenueStatus.FREE)
        self.assertEqual(result.new_status, VenueStatus.BOOKED)
        self.assertEqual(VenueStatusHistory.objects.count(), 1)

    def test_illegal_transition_is_rejected(self):
        # FREE → IN_USE is illegal (must go through BOOKED first).
        with self.assertRaises(IllegalTransition):
            VenueStateMachine(self.venue).transition(
                to_status=VenueStatus.IN_USE,
                event=TransitionEvent.LECTURER_CONFIRMED,
                user=self.admin,
            )
        self.venue.refresh_from_db()
        self.assertEqual(self.venue.status, VenueStatus.FREE)
        self.assertEqual(VenueStatusHistory.objects.count(), 0)

    def test_expire_booking_writes_two_history_rows_and_ends_free(self):
        # Set up: FREE → BOOKED
        VenueStateMachine(self.venue).transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
            user=self.admin,
        )
        # BOOKED → EXPIRED → FREE
        result = VenueStateMachine(self.venue).expire_booking(user=self.admin)

        self.venue.refresh_from_db()
        self.assertEqual(self.venue.status, VenueStatus.FREE)
        self.assertEqual(result.final_status, VenueStatus.FREE)
        # 3 total rows: FREE→BOOKED, BOOKED→EXPIRED, EXPIRED→FREE
        self.assertEqual(VenueStatusHistory.objects.count(), 3)

    def test_maintenance_from_booked_requires_force(self):
        VenueStateMachine(self.venue).transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
            user=self.admin,
        )
        with self.assertRaises(TransitionRequiresForce):
            VenueStateMachine(self.venue).transition(
                to_status=VenueStatus.MAINTENANCE,
                event=TransitionEvent.MAINTENANCE_STARTED,
                user=self.admin,
                reason='Emergency electrical fault',
            )
        # With force=True, it succeeds.
        VenueStateMachine(self.venue).transition(
            to_status=VenueStatus.MAINTENANCE,
            event=TransitionEvent.MAINTENANCE_STARTED,
            user=self.admin,
            reason='Emergency electrical fault',
            force=True,
        )
        self.venue.refresh_from_db()
        self.assertEqual(self.venue.status, VenueStatus.MAINTENANCE)


# ── Safe deactivation ─────────────────────────────────────────────────────────

class DeactivationSafetyTests(APITestCase):
    def setUp(self):
        self.admin = _make_user()
        self.building = _make_building()
        self.venue = _make_venue(self.building)

    def test_deactivate_clean_venue_succeeds(self):
        result = deactivate_venue_safely(self.venue, user=self.admin)
        self.venue.refresh_from_db()
        self.assertFalse(self.venue.is_active)
        self.assertEqual(result['is_active'], False)

    def test_deactivate_in_use_venue_is_refused(self):
        # Drive to IN_USE via legal transitions.
        m = VenueStateMachine(self.venue)
        m.transition(VenueStatus.BOOKED, TransitionEvent.TIMETABLE_ENTRY_CREATED, user=self.admin)
        m.transition(VenueStatus.IN_USE, TransitionEvent.LECTURER_CONFIRMED, user=self.admin)
        with self.assertRaises(VenueHasFutureBookings):
            deactivate_venue_safely(self.venue, user=self.admin)


# ── Alternative finder ────────────────────────────────────────────────────────

class AlternativeFinderTests(APITestCase):
    def setUp(self):
        self.b1 = _make_building('COICT', 'College of ICT')
        self.b2 = _make_building('COET', 'College of Engineering')

        self.lh_big_proj = _make_venue(
            self.b1, code='COICT-LH1', capacity=150,
            venue_type=VenueType.LECTURE_HALL,
            resources=['projector', 'audio_system'],
            accessibility=['wheelchair_access'],
        )
        self.lh_small = _make_venue(
            self.b1, code='COICT-LH2', capacity=60,
            venue_type=VenueType.LECTURE_HALL,
            resources=['projector'],
            accessibility=[],
        )
        self.lab = _make_venue(
            self.b2, code='COET-LAB1', capacity=40,
            venue_type=VenueType.LABORATORY,
            resources=['projector', 'oscilloscopes'],
            accessibility=['wheelchair_access'],
        )

    def test_capacity_and_type_filter(self):
        results = find_alternative_venues(
            capacity_needed=50,
            venue_type=VenueType.LECTURE_HALL,
        )
        codes = [v.code for v in results]
        self.assertIn('COICT-LH1', codes)
        self.assertIn('COICT-LH2', codes)
        self.assertNotIn('COET-LAB1', codes)  # wrong type

    def test_resource_filter_narrows(self):
        results = find_alternative_venues(
            capacity_needed=50,
            venue_type=VenueType.LECTURE_HALL,
            required_resources=['audio_system'],
        )
        codes = [v.code for v in results]
        self.assertEqual(codes, ['COICT-LH1'])

    def test_accessibility_filter_narrows(self):
        results = find_alternative_venues(
            capacity_needed=20,
            required_accessibility=['wheelchair_access'],
        )
        codes = sorted(v.code for v in results)
        self.assertEqual(codes, ['COET-LAB1', 'COICT-LH1'])

    def test_same_building_ranks_first(self):
        results = find_alternative_venues(
            capacity_needed=30,
            same_building_id=self.b1.id,
        )
        self.assertEqual(results[0].building_id, self.b1.id)


# ── API endpoints ─────────────────────────────────────────────────────────────

class VenueAPIEndpointTests(APITestCase):
    def setUp(self):
        self.admin = _make_user(email='admin@utlva.local', role=Role.SYSTEM_ADMIN)
        self.student = _make_user(email='student@utlva.local', role=Role.STUDENT)
        self.building = _make_building()
        self.venue = _make_venue(
            self.building,
            resources=['projector', 'whiteboard'],
            accessibility=['wheelchair_access'],
        )

    def test_dashboard_returns_summary_and_venues(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('venue-dashboard')
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('summary', response.data)
        self.assertIn('venues', response.data)
        self.assertIn('buildings', response.data)
        self.assertEqual(response.data['summary']['total_active_venues'], 1)

    def test_search_resource_filter(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('venue-search')
        response = self.client.get(url, {'resources': 'projector'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)

        response = self.client.get(url, {'resources': 'magic_carpet'})
        self.assertEqual(response.data['count'], 0)

    def test_student_cannot_transition(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('venue-transition', kwargs={'pk': self.venue.pk})
        response = self.client.post(url, {
            'to_status': VenueStatus.BOOKED,
            'event': TransitionEvent.MANUAL_OVERRIDE,
            'reason': 'student trying to do admin work',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_can_transition(self):
        self.client.force_authenticate(user=self.admin)
        url = reverse('venue-transition', kwargs={'pk': self.venue.pk})
        response = self.client.post(url, {
            'to_status': VenueStatus.BOOKED,
            'event': TransitionEvent.MANUAL_OVERRIDE,
            'reason': 'testing transition endpoint',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.venue.refresh_from_db()
        self.assertEqual(self.venue.status, VenueStatus.BOOKED)

    def test_illegal_transition_returns_409(self):
        self.client.force_authenticate(user=self.admin)
        url = reverse('venue-transition', kwargs={'pk': self.venue.pk})
        response = self.client.post(url, {
            'to_status': VenueStatus.IN_USE,
            'event': TransitionEvent.LECTURER_CONFIRMED,
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(response.data['code'], 'ILLEGAL_TRANSITION')

    def test_nearby_returns_within_radius(self):
        self.client.force_authenticate(user=self.student)
        # Venue has no own coords; falls back to building coords (-6.7693, 39.2301).
        url = reverse('venue-nearby')
        response = self.client.get(url, {
            'lat': '-6.7693', 'lng': '39.2301', 'radius_km': '0.5',
        })
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)

    def test_history_endpoint(self):
        self.client.force_authenticate(user=self.admin)
        # Cause two transitions.
        VenueStateMachine(self.venue).transition(
            to_status=VenueStatus.BOOKED,
            event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
            user=self.admin,
        )
        url = reverse('venue-history', kwargs={'pk': self.venue.pk})
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['new_status'], VenueStatus.BOOKED)