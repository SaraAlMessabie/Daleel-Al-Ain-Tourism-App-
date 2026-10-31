class RouteDirection {
  const RouteDirection({
    required this.directionId,
    required this.routeId,
    required this.directionCode,
    required this.destinationEn,
    required this.destinationAr,
  });

  final String directionId;
  final String routeId;
  final String directionCode;
  final String destinationEn;
  final String destinationAr;

  factory RouteDirection.fromMap(Map<String, Object?> map) {
    return RouteDirection(
      directionId: map['direction_id'] as String,
      routeId: map['route_id'] as String,
      directionCode: map['direction_code'] as String? ?? '',
      destinationEn: map['destination_en'] as String? ?? '',
      destinationAr: map['destination_ar'] as String? ?? '',
    );
  }
}

class RouteStopLink {
  const RouteStopLink({
    required this.directionId,
    required this.stopId,
    required this.stopSequence,
  });

  final String directionId;
  final String stopId;
  final int stopSequence;

  factory RouteStopLink.fromMap(Map<String, Object?> map) {
    return RouteStopLink(
      directionId: map['direction_id'] as String,
      stopId: map['stop_id'] as String,
      stopSequence: (map['stop_sequence'] as num).toInt(),
    );
  }
}

class RouteShapePoint {
  const RouteShapePoint({
    required this.directionId,
    required this.pointSequence,
    required this.latitude,
    required this.longitude,
  });

  final String directionId;
  final int pointSequence;
  final double latitude;
  final double longitude;

  factory RouteShapePoint.fromMap(Map<String, Object?> map) {
    return RouteShapePoint(
      directionId: map['direction_id'] as String,
      pointSequence: (map['point_sequence'] as num).toInt(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }
}
