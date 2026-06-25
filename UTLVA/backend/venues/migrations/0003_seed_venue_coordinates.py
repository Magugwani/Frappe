"""
Data migration: seed GPS coordinates, resources, and accessibility for existing venues.

Block A base:  lat=-6.7717  lng=39.2736
Block B base:  lat=-6.7720  lng=39.2740
"""
from decimal import Decimal
from django.db import migrations


_A_LAT = Decimal('-6.7717')
_A_LNG = Decimal('39.2736')
_B_LAT = Decimal('-6.7720')
_B_LNG = Decimal('39.2740')


def seed_forward(apps, schema_editor):
    Venue = apps.get_model('venues', 'Venue')

    updates = [
        {
            'code': 'LH-A101',
            'latitude': _A_LAT + Decimal('0.0001'),
            'longitude': _A_LNG + Decimal('0.0001'),
            'accessibility': ['wheelchair_access'],
        },
        {
            'code': 'CR-A201',
            'latitude': _A_LAT + Decimal('0.0002'),
            'longitude': _A_LNG,
            'resources': ['projector', 'whiteboard'],
        },
        {
            'code': 'SR-A301',
            'latitude': _A_LAT + Decimal('0.0003'),
            'longitude': _A_LNG,
            'resources': ['whiteboard', 'audio_system'],
        },
        {
            'code': 'CL-B101',
            'latitude': _B_LAT + Decimal('0.0001'),
            'longitude': _B_LNG + Decimal('0.0001'),
        },
        {
            'code': 'LB-B201',
            'latitude': _B_LAT + Decimal('0.0002'),
            'longitude': _B_LNG,
        },
        {
            'code': 'CL-I',
            'latitude': _A_LAT,
            'longitude': _A_LNG + Decimal('0.0002'),
            'resources': ['projector', 'whiteboard', 'audio_system'],
            'accessibility': ['wheelchair_access', 'hearing_loop'],
        },
    ]

    for item in updates:
        try:
            venue = Venue.objects.get(code=item['code'])
        except Venue.DoesNotExist:
            continue
        changed = []
        for field in ('latitude', 'longitude', 'resources', 'accessibility'):
            if field in item:
                setattr(venue, field, item[field])
                changed.append(field)
        if changed:
            venue.save(update_fields=changed)

    # BL-15 RWF-3 uses its own building's coordinates
    try:
        bl15 = Venue.objects.get(code='BL-15 RWF-3')
        if bl15.building.latitude and bl15.building.longitude:
            bl15.latitude = bl15.building.latitude
            bl15.longitude = bl15.building.longitude
        bl15.resources = ['projector', 'whiteboard', 'audio_system']
        bl15.save(update_fields=['latitude', 'longitude', 'resources'])
    except Venue.DoesNotExist:
        pass


def seed_reverse(apps, schema_editor):
    Venue = apps.get_model('venues', 'Venue')
    codes = ['LH-A101', 'CR-A201', 'SR-A301', 'CL-B101', 'LB-B201', 'CL-I', 'BL-15 RWF-3']
    for code in codes:
        try:
            v = Venue.objects.get(code=code)
            v.latitude = None
            v.longitude = None
            v.resources = []
            v.accessibility = []
            v.save(update_fields=['latitude', 'longitude', 'resources', 'accessibility'])
        except Venue.DoesNotExist:
            pass


class Migration(migrations.Migration):

    dependencies = [
        ('venues', '0002_venue_status_history'),
    ]

    operations = [
        migrations.RunPython(seed_forward, reverse_code=seed_reverse),
    ]
