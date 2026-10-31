class Category {
  const Category({
    required this.categoryId,
    required this.nameEn,
    required this.nameAr,
    required this.iconPath,
  });

  final int categoryId;
  final String nameEn;
  final String nameAr;
  final String? iconPath;

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      categoryId: map['category_id'] as int,
      nameEn: map['name_en'] as String,
      nameAr: map['name_ar'] as String,
      iconPath: map['icon_path'] as String?,
    );
  }
}
