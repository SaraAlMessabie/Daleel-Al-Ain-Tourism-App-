import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the bundled database. On first launch it is copied from the app's
/// assets to the phone's private storage so it can be written to (quiz answers).
class Db {
  static Database? _db;

  static Future<Database> get() async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'al_ain.db');
    if (!await databaseExists(path)) {
      await Directory(dirname(path)).create(recursive: true);
      final data = await rootBundle.load('assets/db/al_ain.db');
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return openDatabase(
      path,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }
}

/// One row of the attractions table plus the ids of its tags.
class Attraction {
  Attraction(this.row, this.tags);
  final Map<String, Object?> row;
  final Set<int> tags;

  int get id => row['attraction_id'] as int;
  double get price => (row['entry_price_aed'] as num?)?.toDouble() ?? 0;
  double get popularity => (row['popularity_score'] as num?)?.toDouble() ?? 0;
  bool get family => row['is_family_friendly'] == 1;
  bool get unesco => row['unesco_site'] == 1;
  int get categoryId => (row['category_id'] as int?) ?? 0;
  bool get hasLocation => row['latitude'] != null && row['longitude'] != null;
  int? get visitMinutes => row['avg_visit_duration_mins'] as int?;
  String? get modelLabel => row['model_label'] as String?;

  /// pick('ar', 'name') reads name_ar and falls back to name_en if it is empty.
  String pick(String lang, String base) {
    final v = row['${base}_$lang'] as String?;
    if (v != null && v.trim().isNotEmpty) return v;
    return (row['${base}_en'] as String?) ?? '';
  }
}

Future<List<Attraction>> loadAttractions() async {
  final db = await Db.get();
  final rows = await db.query('attractions', where: 'is_active = 1');
  final links = await db.query('attraction_tags');
  final byId = <int, Set<int>>{};
  for (final l in links) {
    (byId[l['attraction_id'] as int] ??= {}).add(l['tag_id'] as int);
  }
  return [for (final r in rows) Attraction(r, byId[r['attraction_id'] as int] ?? {})];
}

/// One attraction by id (used when the map opens a place screen).
Future<Attraction?> loadAttraction(int id) async {
  final db = await Db.get();
  final rows = await db.query('attractions',
      where: 'attraction_id = ?', whereArgs: [id], limit: 1);
  if (rows.isEmpty) return null;
  final links = await db.query('attraction_tags',
      where: 'attraction_id = ?', whereArgs: [id]);
  return Attraction(rows.first, {for (final l in links) l['tag_id'] as int});
}

/// Attraction categories (the same eight the map filters by).
class PlaceCategoryRow {
  const PlaceCategoryRow(this.id, this.en, this.ar);
  final int id;
  final String en, ar;
  String name(String lang) => lang == 'ar' ? ar : en;
}

Future<List<PlaceCategoryRow>> loadCategories() async {
  final db = await Db.get();
  final rows = await db.query('categories', orderBy: 'category_id');
  return [
    for (final r in rows)
      PlaceCategoryRow(r['category_id'] as int, r['name_en'] as String,
          r['name_ar'] as String),
  ];
}

/// Quiz/profile "interests". Each friendly choice saves one or more tag ids.
class Interest {
  const Interest(this.en, this.ar, this.tags);
  final String en, ar;
  final List<int> tags;
}

const interests = [
  Interest('History & heritage', 'التاريخ والتراث', [13, 25]),
  Interest('Art & culture', 'الفنون والثقافة', [1, 9, 7]),
  Interest('Nature & views', 'الطبيعة والمناظر', [4, 16, 21]),
  Interest('Hiking & mountains', 'المشي في الجبال', [15]),
  Interest('Desert & adventure', 'الصحراء والمغامرة', [23, 5]),
  Interest('Wildlife', 'الحياة البرية', [17]),
  Interest('Water activities', 'الأنشطة المائية', [18]),
  Interest('Relax & picnics', 'الاسترخاء والنزهات', [19, 20]),
  Interest('Shopping & markets', 'التسوق والأسواق', [3, 27]),
  Interest('Sports & cycling', 'الرياضة وركوب الدراجات', [24, 22, 10, 11]),
  Interest('Mosques & religious sites', 'المساجد والمواقع الدينية', [14]),
  Interest('Theme parks & fun', 'المتنزهات الترفيهية', [28]),
  Interest('Learning', 'التعلّم', [29]),
  Interest('Festivals & events', 'المهرجانات والفعاليات', [8, 31, 6]),
];

Set<int> tagsOf(Set<int> groups) => {for (final i in groups) ...interests[i].tags};

Set<int> groupsOf(Set<int> tagIds) => {
      for (var i = 0; i < interests.length; i++)
        if (interests[i].tags.every(tagIds.contains)) i,
    };
