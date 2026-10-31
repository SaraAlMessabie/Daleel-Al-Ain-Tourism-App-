import 'package:latlong2/latlong.dart';

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.instructions,
    this.fromOfflineCache = false,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteInstruction> instructions;
  final bool fromOfflineCache;

  double get distanceKm => distanceMeters / 1000;

  int get durationMinutes => (durationSeconds / 60).ceil();

  Map<String, Object?> toMap() => <String, Object?>{
    'points': points
        .map((point) => <double>[point.latitude, point.longitude])
        .toList(),
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'instructions': instructions.map((item) => item.toMap()).toList(),
  };

  factory RoadRoute.fromMap(
    Map<String, Object?> map, {
    bool fromOfflineCache = false,
  }) {
    return RoadRoute(
      points: (map['points'] as List<dynamic>? ?? const []).map((value) {
        final pair = value as List<dynamic>;
        return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList(),
      distanceMeters: (map['distance_meters'] as num).toDouble(),
      durationSeconds: (map['duration_seconds'] as num).toDouble(),
      instructions: (map['instructions'] as List<dynamic>? ?? const [])
          .map(
            (value) => RouteInstruction.fromMap(
              Map<String, Object?>.from(value as Map),
            ),
          )
          .toList(),
      fromOfflineCache: fromOfflineCache,
    );
  }
}

class RouteInstruction {
  const RouteInstruction({
    required this.type,
    required this.modifier,
    required this.roadName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.location,
  });

  final String type;
  final String modifier;
  final String roadName;
  final double distanceMeters;
  final double durationSeconds;
  final LatLng location;

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type,
    'modifier': modifier,
    'road_name': roadName,
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'location': <double>[location.latitude, location.longitude],
  };

  factory RouteInstruction.fromMap(Map<String, Object?> map) {
    final location = map['location'] as List<dynamic>;
    return RouteInstruction(
      type: map['type'] as String? ?? 'continue',
      modifier: map['modifier'] as String? ?? '',
      roadName: map['road_name'] as String? ?? '',
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toDouble() ?? 0,
      location: LatLng(
        (location[0] as num).toDouble(),
        (location[1] as num).toDouble(),
      ),
    );
  }
}
