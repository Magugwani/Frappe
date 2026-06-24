class Building {
  final int id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final int venueCount;

  const Building({
    required this.id,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    required this.venueCount,
  });

  factory Building.fromJson(Map<String, dynamic> j) => Building(
        id: j['id'],
        name: j['name'],
        address: j['address'] ?? '',
        latitude: j['latitude'] != null ? double.tryParse(j['latitude'].toString()) : null,
        longitude: j['longitude'] != null ? double.tryParse(j['longitude'].toString()) : null,
        venueCount: j['venue_count'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
}

class Venue {
  final int id;
  final String code;
  final String name;
  final int buildingId;
  final String buildingName;
  final int floor;
  final int capacity;
  final String venueType;
  final String venueTypeDisplay;
  final List<dynamic> resources;
  final List<dynamic> accessibility;
  final String status;
  final String statusDisplay;
  final bool isActive;
  final double? latitude;
  final double? longitude;

  const Venue({
    required this.id,
    required this.code,
    required this.name,
    required this.buildingId,
    required this.buildingName,
    required this.floor,
    required this.capacity,
    required this.venueType,
    required this.venueTypeDisplay,
    required this.resources,
    required this.accessibility,
    required this.status,
    required this.statusDisplay,
    required this.isActive,
    this.latitude,
    this.longitude,
  });

  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
        id: j['id'],
        code: j['code'],
        name: j['name'],
        buildingId: j['building'],
        buildingName: j['building_name'] ?? '',
        floor: j['floor'] ?? 0,
        capacity: j['capacity'],
        venueType: j['venue_type'],
        venueTypeDisplay: j['venue_type_display'] ?? j['venue_type'],
        resources: j['resources'] ?? [],
        accessibility: j['accessibility'] ?? [],
        status: j['status'],
        statusDisplay: j['status_display'] ?? j['status'],
        isActive: j['is_active'] ?? true,
        latitude: j['latitude'] != null ? double.tryParse(j['latitude'].toString()) : null,
        longitude: j['longitude'] != null ? double.tryParse(j['longitude'].toString()) : null,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'building': buildingId,
        'floor': floor,
        'capacity': capacity,
        'venue_type': venueType,
        'resources': resources,
        'accessibility': accessibility,
        'is_active': isActive,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
}
