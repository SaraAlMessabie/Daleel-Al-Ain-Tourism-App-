// lib/itinerary/itinerary_store.dart
//
// Saves itineraries in the app's own database, in the two tables that were already in the schema
// (`itineraries` and `itinerary_items`, both empty until now). Three small columns are added to
// `itinerary_items` the first time (day_number, slot, note) because the schema had nowhere to say which day a stop
// belongs to; adding a column never touches existing data, and it is done only if the column is missing.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data.dart';
import 'itinerary_core.dart';

class ItinerarySummary {
  const ItinerarySummary({
    required this.id,
    required this.title,
    required this.people,
    required this.total,
    required this.days,
    required this.stops,
  });
  final int id;
  final String title;
  final int people;
  final double total;
  final int days;
  final int stops;
}

class ItineraryStore {
  static bool _schemaReady = false;

  static Future<Database> _open() async {
    final db = await Db.get();
    if (!_schemaReady) {
      final cols = {for (final r in await db.rawQuery('PRAGMA table_info(itinerary_items)')) r['name'] as String};
      const wanted = {'day_number': 'INTEGER', 'slot': 'TEXT', 'note': 'TEXT'};
      for (final c in wanted.entries) {
        if (!cols.contains(c.key)) {
          await db.execute('ALTER TABLE itinerary_items ADD COLUMN ${c.key} ${c.value}');
        }
      }
      _schemaReady = true;
    }
    return db;
  }

  /// Saves the plan (a new itinerary, or replaces the stops of [existingId]). Places that are not in the guide
  /// are not saved. Returns the itinerary's id.
  static Future<int> save(Plan plan, {required String title, int? existingId}) async {
    final db = await _open();
    return db.transaction((txn) async {
      final notes = jsonEncode({
        'dayTitles': {for (final d in plan.days) '${d.number}': d.title},
        'source': 'assistant',
      });
      final values = <String, Object?>{
        'title': title,
        'notes': notes,
        'budget_aed': plan.budgetAed,
        'num_people': plan.people,
        'has_minors': 0,
        'total_cost_aed': plan.total,
      };
      int id;
      if (existingId == null) {
        id = await txn.insert('itineraries', values);
      } else {
        await txn.update('itineraries', values, where: 'itinerary_id = ?', whereArgs: [existingId]);
        await txn.delete('itinerary_items', where: 'itinerary_id = ?', whereArgs: [existingId]);
        id = existingId;
      }
      var order = 0;
      for (final day in plan.days) {
        for (final stop in day.stops) {
          final facts = stop.facts;
          if (facts == null) continue;
          await txn.insert('itinerary_items', {
            'itinerary_id': id,
            'item_type': 'attraction',
            'attraction_id': facts.id,
            'duration_mins': stop.minutes,
            'visit_order': order++,
            'day_number': day.number,
            'slot': stop.slot.name,
            'note': stop.note,
          });
        }
      }
      return id;
    });
  }

  static Future<List<ItinerarySummary>> list() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT i.itinerary_id AS id, i.title AS title, i.num_people AS people, i.total_cost_aed AS total,
             COUNT(t.item_id) AS stops, COALESCE(MAX(t.day_number), 0) AS days
      FROM itineraries i LEFT JOIN itinerary_items t ON t.itinerary_id = i.itinerary_id
      GROUP BY i.itinerary_id ORDER BY i.itinerary_id DESC''');
    return [
      for (final r in rows)
        ItinerarySummary(
          id: (r['id'] as num).toInt(),
          title: (r['title'] as String?) ?? '',
          people: (r['people'] as num?)?.toInt() ?? 1,
          total: (r['total'] as num?)?.toDouble() ?? 0,
          days: (r['days'] as num).toInt(),
          stops: (r['stops'] as num).toInt(),
        ),
    ];
  }

  static Future<Plan?> load(int id) async {
    final db = await _open();
    final head = await db.query('itineraries', where: 'itinerary_id = ?', whereArgs: [id], limit: 1);
    if (head.isEmpty) return null;
    final facts = {for (final a in await loadAttractions()) a.id: PlaceFacts.fromRow(a.row)};
    final items = await db.query('itinerary_items',
        where: 'itinerary_id = ?', whereArgs: [id], orderBy: 'day_number, visit_order');
    final h = head.first;
    final plan = Plan(
      title: h['title'] as String?,
      people: (h['num_people'] as num?)?.toInt() ?? 1,
      budgetAed: (h['budget_aed'] as num?)?.toDouble(),
    );
    var dayTitles = <String, dynamic>{};
    try {
      final n = h['notes'] as String?;
      if (n != null) {
        dayTitles = ((jsonDecode(n) as Map<String, dynamic>)['dayTitles'] as Map<String, dynamic>?) ?? {};
      }
    } catch (_) {
      // notes written by something else: the day titles are simply left out
    }
    final byDay = <int, PlanDay>{};
    for (final it in items) {
      final f = facts[(it['attraction_id'] as num?)?.toInt()];
      if (f == null) continue; // the place is no longer active
      final dayNumber = (it['day_number'] as num?)?.toInt() ?? 1;
      final day = byDay.putIfAbsent(dayNumber, () {
        final d = PlanDay(dayNumber, (dayTitles['$dayNumber'] as String?) ?? '');
        plan.days.add(d);
        return d;
      });
      final slotName = it['slot'] as String?;
      final slot = Slot.values.firstWhere((s) => s.name == slotName, orElse: () => Slot.any);
      day.stops.add(PlanStop(facts: f, name: f.name, slot: slot, note: (it['note'] as String?) ?? ''));
    }
    if (plan.days.isEmpty) plan.days.add(PlanDay(1, ''));
    recheck(plan);
    return plan;
  }

  static Future<void> delete(int id) async {
    final db = await _open();
    await db.delete('itinerary_items', where: 'itinerary_id = ?', whereArgs: [id]);
    await db.delete('itineraries', where: 'itinerary_id = ?', whereArgs: [id]);
  }
}