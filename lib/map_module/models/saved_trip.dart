class SavedTrip {
  const SavedTrip({
    required this.id,
    required this.name,
    required this.attractionIds,
    required this.travelMode,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<int> attractionIds;
  final String travelMode;
  final DateTime createdAt;

  factory SavedTrip.fromMap(Map<String, Object?> map) {
    return SavedTrip(
      id: map['id'] as String,
      name: map['name'] as String,
      attractionIds: (map['attraction_ids'] as List<dynamic>)
          .map((value) => (value as num).toInt())
          .toList(),
      travelMode: map['travel_mode'] as String? ?? 'driving',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'attraction_ids': attractionIds,
      'travel_mode': travelMode,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

enum TravelMode {
  walking,
  driving,
  bus;

  static TravelMode fromStorage(String? value) {
    return TravelMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => TravelMode.driving,
    );
  }
}
