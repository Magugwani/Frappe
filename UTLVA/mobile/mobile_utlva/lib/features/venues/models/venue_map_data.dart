class VenueMapData {
  final int id;
  final String code;
  final String name;
  final String buildingName;
  final int floor;
  final int capacity;
  final String venueType;
  final String venueTypeDisplay;
  final List<dynamic> resources;
  final List<dynamic> accessibility;
  final String status;
  final String statusDisplay;
  final double lat;
  final double lng;

  const VenueMapData({
    required this.id,
    required this.code,
    required this.name,
    required this.buildingName,
    required this.floor,
    required this.capacity,
    required this.venueType,
    required this.venueTypeDisplay,
    required this.resources,
    required this.accessibility,
    required this.status,
    required this.statusDisplay,
    required this.lat,
    required this.lng,
  });

  bool get isAccessible => accessibility.isNotEmpty;

  factory VenueMapData.fromJson(Map<String, dynamic> j) => VenueMapData(
        id: j['id'],
        code: j['code'] ?? '',
        name: j['name'] ?? '',
        buildingName: j['building_name'] ?? '',
        floor: j['floor'] ?? 0,
        capacity: j['capacity'] ?? 0,
        venueType: j['venue_type'] ?? '',
        venueTypeDisplay: j['venue_type_display'] ?? '',
        resources: j['resources'] ?? [],
        accessibility: j['accessibility'] ?? [],
        status: j['status'] ?? 'FREE',
        statusDisplay: j['status_display'] ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}
