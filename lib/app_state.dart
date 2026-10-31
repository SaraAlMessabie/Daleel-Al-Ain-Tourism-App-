import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'strings.dart';

/// Tab order in the home shell. Keep in sync with HomeShell.
class Tabs {
  static const explore = 0;
  static const map = 1;
  static const camera = 2;
  static const profile = 3;
}

/// Holds the user's preferences. Saved in user_preference / user_preference_tags.
/// Also owns the saved places ("favourites"), shared by Explore, the place
/// screen, the map and Profile.
class AppState extends ChangeNotifier {
  String language = 'en';
  String? travelStyle;
  double? budget; // null = no limit
  Set<int> tagIds = {};
  bool quizDone = false;
  int? _prefId;

  // --- Saved places --------------------------------------------------------
  static const _favoritesKey = 'daleel_favorites_v1';
  static const _legacyMapStateKey = 'al_ain_user_state_v1';
  Set<int> favoriteIds = {};

  bool isFavorite(int id) => favoriteIds.contains(id);

  Future<void> toggleFavorite(int id) async {
    favoriteIds = {...favoriteIds};
    if (!favoriteIds.remove(id)) favoriteIds.add(id);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _favoritesKey, [for (final f in favoriteIds) '$f']);
    } catch (_) {
      // Saving is best effort; the in-memory list still works this session.
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_favoritesKey);
      if (saved != null) {
        favoriteIds = saved.map(int.tryParse).whereType<int>().toSet();
        return;
      }
      // First run after this update: bring over favourites saved by the map.
      final legacy = prefs.getString(_legacyMapStateKey);
      if (legacy == null) return;
      final map = jsonDecode(legacy) as Map;
      favoriteIds = {
        for (final v in (map['favorite_ids'] as List? ?? const []))
          (v as num).toInt(),
      };
      await prefs.setStringList(
          _favoritesKey, [for (final f in favoriteIds) '$f']);
    } catch (_) {
      favoriteIds = {};
    }
  }

  // --- Opening the map on a chosen attraction -------------------------------
  int? mapFocusId;
  int mapFocusNonce = 0; // changes on every request, even for the same place
  bool mapFocusDirections = false; // true = open travel options straight away
  int? tabRequest; // the home shell switches to this tab, then clears it

  void showOnMap(int attractionId, {bool directions = false}) {
    mapFocusId = attractionId;
    mapFocusDirections = directions;
    mapFocusNonce++;
    tabRequest = Tabs.map;
    notifyListeners();
  }

  void clearTabRequest() => tabRequest = null; // no rebuild needed

  String t(String key) => T.of(language, key);

  Future<void> load() async {
    await _loadFavorites();
    final db = await Db.get();
    final rows = await db.query('user_preference', orderBy: 'pref_id DESC', limit: 1);
    if (rows.isEmpty) return; // first launch: no quiz answers yet
    final r = rows.first;
    _prefId = r['pref_id'] as int;
    language = (r['language'] as String?) ?? 'en';
    travelStyle = r['travel_style'] as String?;
    budget = (r['budget_aed'] as num?)?.toDouble();
    final tg = await db.query('user_preference_tags',
        where: 'pref_id = ?', whereArgs: [_prefId]);
    tagIds = {for (final e in tg) e['tag_id'] as int};
    quizDone = true;
  }

  /// Switches the language on screen right away (used while answering the quiz).
  void setLanguage(String lang) {
    language = lang;
    notifyListeners();
  }

  Future<void> save({
    required String lang,
    required String? style,
    required double? budget,
    required Set<int> tags,
  }) async {
    final db = await Db.get();
    language = lang;
    travelStyle = style;
    this.budget = budget;
    tagIds = {...tags};
    await db.transaction((txn) async {
      final values = <String, Object?>{
        'budget_aed': budget,
        'language': lang,
        'travel_style': style,
        'interests_json': jsonEncode(tags.toList()..sort()),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_prefId == null) {
        _prefId = await txn.insert('user_preference', values);
      } else {
        await txn.update('user_preference', values,
            where: 'pref_id = ?', whereArgs: [_prefId]);
      }
      await txn.delete('user_preference_tags',
          where: 'pref_id = ?', whereArgs: [_prefId]);
      for (final id in tags) {
        await txn.insert('user_preference_tags', {'pref_id': _prefId, 'tag_id': id});
      }
    });
    quizDone = true;
    notifyListeners();
  }
}
