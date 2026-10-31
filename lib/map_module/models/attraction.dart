class Attraction {
  const Attraction({
    required this.attractionId,
    required this.categoryId,
    required this.nameEn,
    required this.nameAr,
    required this.latitude,
    required this.longitude,
    required this.entryPriceAed,
    required this.openingHours,
    required this.dressCodeNote,
    required this.imagePath,
    required this.isFamilyFriendly,
    required this.isActive,
  });

  final int attractionId;
  final int categoryId;

  final String nameEn;
  final String nameAr;

  final double latitude;
  final double longitude;
  final double entryPriceAed;

  final String? openingHours;
  final String? dressCodeNote;
  final String? imagePath;

  final bool isFamilyFriendly;
  final bool isActive;

  factory Attraction.fromMap(Map<String, Object?> map) {
    return Attraction(
      attractionId: map['attraction_id'] as int,
      categoryId: map['category_id'] as int,
      nameEn: map['name_en'] as String,
      nameAr: map['name_ar'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      entryPriceAed: (map['entry_price_aed'] as num?)?.toDouble() ?? 0,
      openingHours: map['opening_hours'] as String?,
      dressCodeNote: map['dress_code_note'] as String?,
      imagePath: map['image_path'] as String?,
      isFamilyFriendly: (map['is_family_friendly'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'attraction_id': attractionId,
      'category_id': categoryId,
      'name_en': nameEn,
      'name_ar': nameAr,
      'latitude': latitude,
      'longitude': longitude,
      'entry_price_aed': entryPriceAed,
      'opening_hours': openingHours,
      'dress_code_note': dressCodeNote,
      'image_path': imagePath,
      'is_family_friendly': isFamilyFriendly ? 1 : 0,
      'is_active': isActive ? 1 : 0,
    };
  }
}
