class BusStop {
  const BusStop({
    required this.stopId,
    required this.nameEn,
    required this.nameAr,
    required this.latitude,
    required this.longitude,
    this.stopCode,
  });

  final String stopId;
  final String? stopCode;
  final String nameEn;
  final String nameAr;
  final double latitude;
  final double longitude;

  factory BusStop.fromMap(Map<String, Object?> map) {
    return BusStop(
      stopId: map['stop_id'] as String,
      stopCode: map['stop_code'] as String?,
      nameEn: map['name_en'] as String,
      nameAr: map['name_ar'] as String? ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }
}
