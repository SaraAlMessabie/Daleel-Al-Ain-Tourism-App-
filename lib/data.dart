import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the bundled database. On first launch it is copied from the app's
/// assets to the phone's private storage so it can be written to (quiz answers).
///
/// When an app update ships newer data (places, prices, hours), raise [bundledDbVersion]. On the next start the new
/// database is copied in and the user's own rows (quiz answers, saved itineraries, interaction log) are carried over.
/// If anything goes wrong during that, the old database is left untouched and keeps being used.
class Db {
  static Database? _db;

  /// Raise this number every time assets/db/al_ain.db changes.
  static const bundledDbVersion = 3;
  static const _versionKey = 'daleel_db_version';

  /// Tables that hold the user's own data. Everything else comes from the bundled database.
  static const _userTables = [
    'user_preference',
    'user_preference_tags',
    'itineraries',
    'itinerary_items',
    'interaction_log',
  ];

  static Future<Database> get() async => _db ??= await _open();

  static Future<void> _copyAssetTo(String target) async {
    await Directory(dirname(target)).create(recursive: true);
    final data = await rootBundle.load('assets/db/al_ain.db');
    // Write to a temporary file first and rename it when complete, so an app killed halfway through the copy
    // never leaves a half-written database that would be treated as valid on the next start.
    final tmp = File('$target.tmp');
    await tmp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await tmp.rename(target);
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'al_ain.db');
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    if (!await databaseExists(path)) {
      await _copyAssetTo(path);
      await prefs?.setInt(_versionKey, bundledDbVersion);
    } else if ((prefs?.getInt(_versionKey) ?? 1) < bundledDbVersion) {
      try {
        await _upgrade(path);
        await prefs?.setInt(_versionKey, bundledDbVersion);
      } catch (e, st) {
        // Keep the old database; the upgrade is tried again on the next start.
        debugPrint('Database upgrade failed, keeping the old one: $e\n$st');
      }
    }
    return openDatabase(
      path,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  /// Builds a fresh copy from the assets, moves the user's rows into it, then swaps it in for the old file.
  static Future<void> _upgrade(String path) async {
    final fresh = '$path.new';
    if (await databaseExists(fresh)) await deleteDatabase(fresh);
    await _copyAssetTo(fresh);
    final db = await openDatabase(fresh);
    try {
      // ItineraryStore adds these three columns to the old database; the new one needs them too.
      final itemCols = {for (final r in await db.rawQuery('PRAGMA table_info(itinerary_items)')) r['name'] as String};
      const extra = {'day_number': 'INTEGER', 'slot': 'TEXT', 'note': 'TEXT'};
      for (final c in extra.entries) {
        if (!itemCols.contains(c.key)) await db.execute('ALTER TABLE itinerary_items ADD COLUMN ${c.key} ${c.value}');
      }
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute("ATTACH DATABASE '${path.replaceAll("'", "''")}' AS old");
      await db.transaction((txn) async {
        for (final table in _userTables) {
          final oldCols = {for (final r in await txn.rawQuery('PRAGMA old.table_info($table)')) r['name'] as String};
          final newCols = [for (final r in await txn.rawQuery('PRAGMA main.table_info($table)')) r['name'] as String];
          final shared = [for (final c in newCols) if (oldCols.contains(c)) c];
          if (shared.isEmpty) continue;
          final list = shared.join(', ');
          await txn.execute('INSERT INTO main.$table ($list) SELECT $list FROM old.$table');
        }
        // A place or tag removed from the new data must not block the update: drop the user's rows that point to it
        // (they could no longer be shown anyway), instead of failing the update on every start.
        await txn.execute('DELETE FROM main.itinerary_items WHERE attraction_id IS NOT NULL '
            'AND attraction_id NOT IN (SELECT attraction_id FROM main.attractions)');
        await txn.execute('DELETE FROM main.itinerary_items WHERE event_id IS NOT NULL '
            'AND event_id NOT IN (SELECT event_id FROM main.events)');
        await txn.execute('DELETE FROM main.user_preference_tags WHERE tag_id NOT IN (SELECT tag_id FROM main.tags)');
        final broken = await txn.rawQuery('PRAGMA foreign_key_check');
        if (broken.isNotEmpty) throw StateError('foreign key problems after the copy: $broken');
      });
      await db.execute('DETACH DATABASE old');
    } finally {
      await db.close();
    }
    // Only now is the old file replaced.
    await File(fresh).rename(path);
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
