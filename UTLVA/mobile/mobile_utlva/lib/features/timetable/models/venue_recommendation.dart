class VenueRecommendation {
  final int id;
  final String code;
  final String name;
  final String buildingName;
  final int capacity;
  final String venueType;
  final String venueTypeDisplay;
  final List<dynamic> resources;
  final int utilizationPct;
  final String fitLabel;

  const VenueRecommendation({
    required this.id,
    required this.code,
    required this.name,
    required this.buildingName,
    required this.capacity,
    required this.venueType,
    required this.venueTypeDisplay,
    required this.resources,
    required this.utilizationPct,
    required this.fitLabel,
  });

  factory VenueRecommendation.fromJson(Map<String, dynamic> j) =>
      VenueRecommendation(
        id: j['id'] as int,
        code: j['code'] as String,
        name: j['name'] as String,
        buildingName: j['building_name'] as String? ?? '',
        capacity: j['capacity'] as int,
        venueType: j['venue_type'] as String,
        venueTypeDisplay: j['venue_type_display'] as String? ?? j['venue_type'] as String,
        resources: j['resources'] as List<dynamic>? ?? [],
        utilizationPct: j['utilization_pct'] as int? ?? 0,
        fitLabel: j['fit_label'] as String? ?? '',
      );
}

class VenueRecommendationResult {
  final List<VenueRecommendation> recommended;
  final String? notFoundReason;
  final int studentsCount;
  final Map<String, int> capacityRange;

  const VenueRecommendationResult({
    required this.recommended,
    this.notFoundReason,
    required this.studentsCount,
    required this.capacityRange,
  });

  bool get hasRecommendations => recommended.isNotEmpty;

  factory VenueRecommendationResult.fromJson(Map<String, dynamic> j) =>
      VenueRecommendationResult(
        recommended: (j['recommended'] as List<dynamic>)
            .map((e) => VenueRecommendation.fromJson(e as Map<String, dynamic>))
            .toList(),
        notFoundReason: j['not_found_reason'] as String?,
        studentsCount: j['students_count'] as int? ?? 0,
        capacityRange: (j['capacity_range'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as int)) ??
            {'min': 0, 'max': 0},
      );
}
