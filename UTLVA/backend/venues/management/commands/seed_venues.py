"""
UTLVA — seed realistic buildings, venues, and a starter status-history row.

Run:
    python manage.py seed_venues
    python manage.py seed_venues --reset    # wipe and re-seed

Coordinates are real downtown Dar es Salaam university-area points; adjust
to your campus when you have surveyed coordinates.
"""

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction

from venues.models import (
    Building,
    Venue,
    VenueStatus,
    VenueStatusHistory,
    VenueType,
    TransitionEvent,
)


# ── Seed data ─────────────────────────────────────────────────────────────────

BUILDINGS = [
    {
        'code': 'COICT',
        'name': 'College of ICT',
        'description': 'CoICT main building, UDSM Kijitonyama campus.',
        'address': 'Kijitonyama, Dar es Salaam',
        'latitude': Decimal('-6.769320'),
        'longitude': Decimal('39.230110'),
    },
    {
        'code': 'COET',
        'name': 'College of Engineering and Technology',
        'description': 'CoET building with workshops and laboratories.',
        'address': 'University of Dar es Salaam main campus',
        'latitude': Decimal('-6.776800'),
        'longitude': Decimal('39.211200'),
    },
    {
        'code': 'LIB-A',
        'name': 'Main Library',
        'description': 'Central library; group study and seminar rooms.',
        'address': 'University of Dar es Salaam main campus',
        'latitude': Decimal('-6.777950'),
        'longitude': Decimal('39.207900'),
    },
    {
        'code': 'COSS',
        'name': 'College of Social Sciences',
        'description': 'CoSS lecture halls.',
        'address': 'University of Dar es Salaam main campus',
        'latitude': Decimal('-6.778400'),
        'longitude': Decimal('39.210500'),
    },
]


def _venues_for(building_code: str):
    """Return the list of venue dicts that belong to a building."""
    if building_code == 'COICT':
        return [
            {
                'code': 'COICT-LH1', 'name': 'Lecture Hall 1',
                'floor': 0, 'indoor_identifier': 'Ground floor, north wing',
                'capacity': 200, 'venue_type': VenueType.LECTURE_HALL,
                'resources': ['projector', 'audio_system', 'whiteboard', 'microphone'],
                'accessibility': ['wheelchair_access', 'hearing_loop'],
                'latitude': Decimal('-6.769310'), 'longitude': Decimal('39.230080'),
            },
            {
                'code': 'COICT-LH2', 'name': 'Lecture Hall 2',
                'floor': 0, 'indoor_identifier': 'Ground floor, south wing',
                'capacity': 150, 'venue_type': VenueType.LECTURE_HALL,
                'resources': ['projector', 'audio_system', 'whiteboard'],
                'accessibility': ['wheelchair_access'],
            },
            {
                'code': 'COICT-CL1', 'name': 'Computer Lab 1',
                'floor': 1, 'indoor_identifier': 'First floor, room 101',
                'capacity': 40, 'venue_type': VenueType.COMPUTER_LAB,
                'resources': ['computers_40', 'projector', 'whiteboard', 'air_conditioning'],
                'accessibility': ['elevator_access'],
            },
            {
                'code': 'COICT-CL2', 'name': 'Computer Lab 2',
                'floor': 1, 'indoor_identifier': 'First floor, room 102',
                'capacity': 30, 'venue_type': VenueType.COMPUTER_LAB,
                'resources': ['computers_30', 'projector', 'air_conditioning'],
                'accessibility': ['elevator_access'],
            },
            {
                'code': 'COICT-SR1', 'name': 'Seminar Room 1',
                'floor': 2, 'indoor_identifier': 'Second floor, room 201',
                'capacity': 25, 'venue_type': VenueType.SEMINAR_ROOM,
                'resources': ['projector', 'whiteboard', 'conference_phone'],
                'accessibility': ['elevator_access'],
            },
        ]
    if building_code == 'COET':
        return [
            {
                'code': 'COET-LAB1', 'name': 'Electronics Lab',
                'floor': 0, 'indoor_identifier': 'Workshop block, ground floor',
                'capacity': 30, 'venue_type': VenueType.LABORATORY,
                'resources': [
                    'oscilloscopes_15', 'soldering_stations_20',
                    'signal_generators_15', 'power_supplies',
                ],
                'accessibility': ['wheelchair_access'],
            },
            {
                'code': 'COET-LAB2', 'name': 'Mechanical Workshop',
                'floor': 0, 'indoor_identifier': 'Workshop block, west side',
                'capacity': 25, 'venue_type': VenueType.LABORATORY,
                'resources': ['lathes_8', 'mills_4', 'safety_equipment'],
                'accessibility': [],
            },
            {
                'code': 'COET-LH1', 'name': 'Engineering Lecture Hall',
                'floor': 1, 'indoor_identifier': 'First floor, central',
                'capacity': 180, 'venue_type': VenueType.LECTURE_HALL,
                'resources': ['projector', 'audio_system', 'document_camera'],
                'accessibility': ['wheelchair_access', 'elevator_access'],
            },
        ]
    if building_code == 'LIB-A':
        return [
            {
                'code': 'LIB-SR1', 'name': 'Library Seminar Room A',
                'floor': 1, 'indoor_identifier': 'First floor, west wing',
                'capacity': 20, 'venue_type': VenueType.SEMINAR_ROOM,
                'resources': ['projector', 'whiteboard'],
                'accessibility': ['wheelchair_access', 'hearing_loop'],
            },
            {
                'code': 'LIB-SR2', 'name': 'Library Seminar Room B',
                'floor': 1, 'indoor_identifier': 'First floor, east wing',
                'capacity': 15, 'venue_type': VenueType.SEMINAR_ROOM,
                'resources': ['smart_board', 'whiteboard'],
                'accessibility': ['wheelchair_access'],
            },
        ]
    if building_code == 'COSS':
        return [
            {
                'code': 'COSS-LH1', 'name': 'Nkrumah Hall',
                'floor': 0, 'indoor_identifier': 'Main hall, ground floor',
                'capacity': 400, 'venue_type': VenueType.AUDITORIUM,
                'resources': ['projector', 'audio_system', 'microphone', 'stage_lighting'],
                'accessibility': ['wheelchair_access', 'hearing_loop'],
            },
            {
                'code': 'COSS-CR1', 'name': 'Classroom 1',
                'floor': 1, 'indoor_identifier': 'First floor, room 110',
                'capacity': 60, 'venue_type': VenueType.CLASSROOM,
                'resources': ['projector', 'whiteboard'],
                'accessibility': [],
            },
            {
                'code': 'COSS-CR2', 'name': 'Classroom 2',
                'floor': 1, 'indoor_identifier': 'First floor, room 112',
                'capacity': 50, 'venue_type': VenueType.CLASSROOM,
                'resources': ['projector', 'whiteboard'],
                'accessibility': [],
            },
        ]
    return []


class Command(BaseCommand):
    help = 'Seed UTLVA buildings, venues, and an initial status-history baseline.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--reset', action='store_true',
            help='Delete all existing venues, buildings, and history before seeding.',
        )

    @transaction.atomic
    def handle(self, *args, **opts):
        if opts['reset']:
            VenueStatusHistory.objects.all().delete()
            Venue.objects.all().delete()
            Building.objects.all().delete()
            self.stdout.write(self.style.WARNING('Existing data wiped.'))

        created_buildings = 0
        created_venues = 0

        for b in BUILDINGS:
            building, was_created = Building.objects.update_or_create(
                code=b['code'],
                defaults={
                    'name': b['name'],
                    'description': b['description'],
                    'address': b['address'],
                    'latitude': b['latitude'],
                    'longitude': b['longitude'],
                    'is_active': True,
                },
            )
            if was_created:
                created_buildings += 1

            for v in _venues_for(b['code']):
                venue, v_created = Venue.objects.update_or_create(
                    code=v['code'],
                    defaults={
                        'name': v['name'],
                        'building': building,
                        'floor': v['floor'],
                        'indoor_identifier': v.get('indoor_identifier', ''),
                        'capacity': v['capacity'],
                        'venue_type': v['venue_type'],
                        'resources': v.get('resources', []),
                        'accessibility': v.get('accessibility', []),
                        'latitude': v.get('latitude'),
                        'longitude': v.get('longitude'),
                        'status': VenueStatus.FREE,
                        'is_active': True,
                    },
                )
                if v_created:
                    created_venues += 1
                    VenueStatusHistory.objects.create(
                        venue=venue,
                        previous_status=None,
                        new_status=VenueStatus.FREE,
                        triggered_by_event=TransitionEvent.SEEDED,
                        reason='Initial venue creation via seed_venues.',
                    )

        self.stdout.write(self.style.SUCCESS(
            f'Done. Buildings created: {created_buildings} '
            f'(total {Building.objects.count()}). '
            f'Venues created: {created_venues} '
            f'(total {Venue.objects.count()}).'
        ))