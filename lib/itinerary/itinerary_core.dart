// lib/itinerary/itinerary_core.dart
//
// Turns the assistant's written plan into a real itinerary, in two steps that need no model:
//   1. extractPlan: reads the answer (Day 1, Day 2 ... with Morning / Afternoon / Evening and the places named)
//      and matches the places to Daleel's own places by name.
//   2. recheck: looks every stop up in the database and adds the facts: price, visit time, opening hours, and
//      warnings (closed in that part of the day, repeated, not in Daleel's guide, too full a day, over budget).
//
// The model decides WHAT to visit and in what order; this file never second-guesses that. It only reads the
// answer, adds facts and does the arithmetic a small model gets wrong. Pure Dart, tested by
// tool/itinerary_selftest.dart on real replies.

enum Slot { morning, afternoon, evening, any }

/// The part of the day a slot stands for, in minutes after midnight.
const _slotStart = {Slot.morning: 540, Slot.afternoon: 720, Slot.evening: 1020};
const _slotEnd = {Slot.morning: 720, Slot.afternoon: 1020, Slot.evening: 1260};

/// A place needs to be open within this long of the slot's start (or end) to count as open for it.
const _slackMinutes = 60;

/// More than this many minutes of visits in one day is flagged.
const _longDayMinutes = 540;

// ---------------------------------------------------------------------------------------------
// Facts about a place (one database row)
// ---------------------------------------------------------------------------------------------

class PlaceFacts {
  const PlaceFacts({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.priceAed = 0,
    this.visitMinutes,
    this.hoursText = '',
    this.closedText = '',
    this.hoursTextAr = '',
    this.closedTextAr = '',
    this.openMinutes,
    this.closeMinutes,
    this.is24h = false,
  });

  /// From a row of the attractions table (the app's `Attraction.row`).
  factory PlaceFacts.fromRow(Map<String, Object?> r) => PlaceFacts(
        id: (r['attraction_id'] as num).toInt(),
        name: (r['name_en'] as String?) ?? '',
        nameAr: (r['name_ar'] as String?) ?? '',
        priceAed: (r['entry_price_aed'] as num?)?.toDouble() ?? 0,
        visitMinutes: (r['avg_visit_duration_mins'] as num?)?.toInt(),
        hoursText: (r['opening_hours'] as String?) ?? '',
        closedText: (r['closed_days'] as String?) ?? '',
        hoursTextAr: (r['opening_hours_ar'] as String?) ?? '',
        closedTextAr: (r['closed_days_ar'] as String?) ?? '',
        openMinutes: parseClock(r['open_time']),
        closeMinutes: parseClock(r['close_time']),
        is24h: r['is_24_hours'] == 1 || r['is_24_hours'] == true,
      );

  final int id;
  final String name;
  final String nameAr;
  final double priceAed;
  final int? visitMinutes;
  final String hoursText;
  final String closedText;

  /// Arabic versions (empty when the database has none; then the English text is shown).
  final String hoursTextAr;
  final String closedTextAr;

  String hours(String lang) => lang == 'ar' && hoursTextAr.trim().isNotEmpty ? hoursTextAr : hoursText;
  final int? openMinutes;
  final int? closeMinutes;
  final bool is24h;

  /// "09:00" gives 540. Null if missing or not a clock time.
  static int? parseClock(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v.trim());
    return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  /// The database's note on closed days, or null when it says there is nothing to note.
  String? get closedNote {
    final t = closedText.trim();
    final l = t.toLowerCase();
    return (t.isEmpty || l == 'none' || l == 'none reported') ? null : t;
  }

  /// [closedNote] in the app's language.
  String? closedNoteIn(String lang) {
    final note = closedNote;
    if (note == null) return null;
    return lang == 'ar' && closedTextAr.trim().isNotEmpty ? closedTextAr : note;
  }
}

String clockText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 || h == 24 ? 'AM' : 'PM'}';
}

// ---------------------------------------------------------------------------------------------
// The plan
// ---------------------------------------------------------------------------------------------

enum WarnKind { opensLater, closesEarlier, repeated, notInGuide, longDay, overBudget }

class Warn {
  const Warn(this.kind, [this.detail = '']);
  final WarnKind kind;

  /// opensLater / closesEarlier: the time ("4:00 PM"); repeated: "Day 2"; longDay: hours ("10.5");
  /// overBudget: the amount over, in AED.
  final String detail;
}

class PlanStop {
  PlanStop({this.facts, required this.name, this.slot = Slot.any, this.note = ''});

  /// Null: the answer named a place that is not in Daleel's guide.
  PlaceFacts? facts;
  String name;
  Slot slot;
  String note;
  final List<Warn> warnings = [];

  bool get inGuide => facts != null;
  int? get placeId => facts?.id;
  double get price => facts?.priceAed ?? 0;
  int get minutes => facts?.visitMinutes ?? 60;
}

class PlanDay {
  PlanDay(this.number, this.title);
  int number;
  String title;
  final List<PlanStop> stops = [];
  final List<Warn> warnings = [];

  int get minutes => stops.fold(0, (a, s) => a + s.minutes);
  double get pricePerPerson => stops.fold(0.0, (a, s) => a + s.price);
}

class Plan {
  Plan({this.title, this.people = 2, this.budgetAed});
  String? title;
  int people;

  /// Null: no limit.
  double? budgetAed;
  final List<PlanDay> days = [];
  final List<Warn> warnings = [];

  double get pricePerPerson => days.fold(0.0, (a, d) => a + d.pricePerPerson);
  double get total => pricePerPerson * people;
  int get stopCount => days.fold(0, (a, d) => a + d.stops.length);
}

// ---------------------------------------------------------------------------------------------
// Matching names in the text to places
// ---------------------------------------------------------------------------------------------

/// Arabic-Indic digits (٠-٩) as 0-9, so "اليوم ١" reads as day 1.
String westernDigits(String s) => s.replaceAllMapped(
    RegExp('[\u0660-\u0669]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0660 + 0x30));

/// Spellings of the same Arabic letter treated as one (أ إ آ = ا, ة = ه, ى = ي), one character for one, so
/// positions found in the folded text are the same in the original.
String foldArabic(String s) => s
    .replaceAll(RegExp('[\u0623\u0625\u0622]'), '\u0627')
    .replaceAll('\u0629', '\u0647')
    .replaceAll('\u0649', '\u064A');

String _norm(String s) => foldArabic(s)
    .toLowerCase()
    .replaceAll(RegExp('[\u2019\u2018\u02BC`]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _boundary(String t, int i) => i < 0 || i >= t.length || !_letterOrDigit.hasMatch(t[i]);

/// Other names people (and the model) use for a place. Keyed by the place's name without brackets, lower case.
const _manualAliases = <String, List<String>>{
  'jebel hafeet': ['Jabal Hafeet', 'Jebel Hafit', 'Jabal Hafit', 'Jebel Hafeet Desert Park', 'Jebel Hafeet National Park', 'Jebel Hafeet Desert Park & Tombs'],
  'al ain national museum': ['Al Ain Museum', 'National Museum of Al Ain'],
  'al ain palace museum': ['Sheikh Zayed Palace Museum', 'Al Ain Palace'],
  'sheikh khalifa bin zayed al nahyan mosque': ['Grand Mosque', 'Al Ain Grand Mosque', 'Sheikh Khalifa Mosque', 'Sheikh Khalifa Grand Mosque'],
  'green mubazzarah hot springs': ['Green Mubazzarah', 'Mubazzarah Hot Springs'],
  'sheikh zayed desert learning centre': ['Desert Learning Centre', 'Desert Learning Center', 'Sheikh Zayed Desert Learning Center'],
  'wadi adventure': ['Al Ain Adventure', 'Wadi Adventure Park'],
  'qasr al muwaiji': ['Muwaiji Fort', 'Al Muwaiji Fort'],
  'al qattara arts centre': ['Qattara Arts Centre', 'Al Qattara Arts Center', 'Qattara Arts Center'],
  'souq al qattara': ['Qattara Souq', 'Al Qattara Souq', 'Al Qattara Heritage Souq'],
  'hili archaeological park': ['Hili Park', 'Hili Archaeological Gardens'],
};

const _typeWords = ['fort', 'park', 'museum', 'mall', 'centre', 'center', 'market', 'track', 'mosque', 'hot springs', 'springs'];

class Mention {
  const Mention(this.place, this.start, this.end);
  final PlaceFacts place;
  final int start;
  final int end;
}

class PlaceIndex {
  PlaceIndex(this.places) {
    // Exact names always win. Derived shortenings ("National Museum") count only if exactly one place claims them.
    final exact = <String, PlaceFacts>{};
    for (final p in places) {
      for (final n in _exactNames(p)) {
        final k = _norm(n);
        if (k.length >= 3) exact[k] = p;
      }
    }
    final claims = <String, Set<int>>{};
    for (final p in places) {
      for (final a in _derivedAliases(p)) {
        final k = _norm(a);
        if (k.length < 4 || exact.containsKey(k)) continue;
        (claims[k] ??= {}).add(p.id);
      }
    }
    final byId = {for (final p in places) p.id: p};
    _alias = {...exact};
    for (final e in claims.entries) {
      if (e.value.length == 1) _alias[e.key] = byId[e.value.first]!;
    }
    _keys = _alias.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  final List<PlaceFacts> places;
  late final Map<String, PlaceFacts> _alias;
  late final List<String> _keys;

  static String _base(String name) => name.replaceAll(RegExp(r'\s*[(\uFF08].*?[)\uFF09]'), '').trim();

  static Iterable<String> _exactNames(PlaceFacts p) sync* {
    yield p.name;
    final base = _base(p.name);
    yield base;
    if (p.nameAr.trim().isNotEmpty) {
      yield p.nameAr;
      yield _base(p.nameAr);
    }
    for (final a in _manualAliases[_norm(base)] ?? const <String>[]) {
      yield a;
    }
  }

  static Iterable<String> _derivedAliases(PlaceFacts p) sync* {
    // Names inside brackets: "Al Aankah Fort (Al A'ankah / Alanka)" and "Al Basra Park (Ladies Park)".
    for (final m in RegExp(r'[(\uFF08](.*?)[)\uFF09]').allMatches(p.name)) {
      for (final part in m.group(1)!.split('/')) {
        yield part.trim();
      }
    }
    final base = _base(p.name);
    var words = base.split(' ');
    final variants = <String>{};
    // A shortened name must keep at least two words, or "Al Ain Mall" would become "Mall" and match every mall.
    if (words.length >= 4 && _norm(words.first) == 'al' && _norm(words[1]) == 'ain') {
      variants.add(words.sublist(2).join(' '));
    }
    if (words.length >= 3 && _norm(words.first) == 'qasr') variants.add(words.sublist(1).join(' '));
    for (final v in {base, ...variants}) {
      yield v;
      for (final t in _typeWords) {
        final n = _norm(v);
        if (n.endsWith(' $t')) {
          final cut = v.substring(0, v.length - t.length).trim();
          if (cut.split(' ').length >= 2) yield cut;
        }
      }
    }
    // spelling: Centre / Center
    if (_norm(base).contains('centre')) yield base.replaceAll(RegExp('centre', caseSensitive: false), 'Center');
  }

  /// The places named in the text, in the order they appear. The longest name wins where two overlap.
  List<Mention> find(String text) {
    final t = _norm(text);
    final candidates = <Mention>[];
    for (final key in _keys) {
      var i = t.indexOf(key);
      while (i != -1) {
        if (_boundary(t, i - 1) && _boundary(t, i + key.length)) {
          candidates.add(Mention(_alias[key]!, i, i + key.length));
        }
        i = t.indexOf(key, i + 1);
      }
    }
    candidates.sort((a, b) {
      final c = (b.end - b.start).compareTo(a.end - a.start);
      return c != 0 ? c : a.start.compareTo(b.start);
    });
    final accepted = <Mention>[];
    for (final c in candidates) {
      if (accepted.every((a) => c.end <= a.start || c.start >= a.end)) accepted.add(c);
    }
    accepted.sort((a, b) => a.start.compareTo(b.start));
    return accepted;
  }
}

// ---------------------------------------------------------------------------------------------
// Reading the answer
// ---------------------------------------------------------------------------------------------

class ExtractResult {
  const ExtractResult(this.plan, this.isPlan, this.matchedStops, this.dayHeadings);
  final Plan plan;

  /// True if the answer reads like a plan (or a list of places worth saving as one).
  final bool isPlan;
  final int matchedStops;
  final int dayHeadings;
}

String _clean(String line) {
  var s = line.replaceAll(RegExp(r'[*_`#]+'), '').trim();
  s = s.replaceFirst(RegExp(r'^[-\u2022]\s+'), '').trim();
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

bool _isBullet(String raw) => RegExp(r'^\s*([-*\u2022]\s+|\d{1,2}[.)]\s+)').hasMatch(raw);

Slot _detectSlot(String text) {
  final head = (text.length > 32 ? text.substring(0, 32) : text).toLowerCase();
  if (RegExp(r'morning|breakfast|sunrise|dawn|صباح').hasMatch(head)) return Slot.morning;
  if (RegExp(r'afternoon|lunch|noon|midday|ظهر|عصر').hasMatch(head)) return Slot.afternoon;
  if (RegExp(r'evening|dinner|night|sunset|مساء|ليل|عشاء').hasMatch(head)) return Slot.evening;
  final m = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|ص|م)(?![A-Za-z])').firstMatch(head);
  if (m != null) {
    var h = int.parse(m.group(1)!);
    final suffix = m.group(3)!;
    final pm = suffix == 'pm' || suffix == 'p.m.' || suffix == 'م';
    if (pm && h < 12) h += 12;
    if (!pm && h == 12) h = 0;
    return h < 12 ? Slot.morning : (h < 17 ? Slot.afternoon : Slot.evening);
  }
  return Slot.any;
}

bool _isLabel(String bold) {
  final t = bold.trim();
  if (t.endsWith(':') || t.endsWith('\uFF1A')) return true;
  return _detectSlot(t) != Slot.any && t.split(' ').length <= 5 && RegExp(r'^\W*(morning|afternoon|evening|night|lunch|dinner|breakfast|\d)', caseSensitive: false).hasMatch(t);
}

/// A bold phrase that looks like a place's name: 2 to 6 words, each starting with a capital (or a small joining word).
bool _looksLikePlaceName(String bold) {
  final words = bold.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (words.length < 2 || words.length > 6) return false;
  if (RegExp(r'\d').hasMatch(bold)) return false;
  const joiners = {'of', 'the', 'al', 'bin', 'and', '&', 'at', 'in'};
  for (final w in words) {
    if (joiners.contains(w.toLowerCase())) continue;
    final c = w.codeUnitAt(0);
    final upper = (c >= 0x41 && c <= 0x5A) || (c >= 0x0600 && c <= 0x06FF);
    if (!upper) return false;
  }
  return true;
}

String _stopNote(String text) {
  var s = text;
  final colon = s.indexOf(':');
  if (colon != -1 && colon <= 32) s = s.substring(colon + 1).trim();
  if (s.length > 200) {
    final cut = s.lastIndexOf(' ', 200);
    s = '${s.substring(0, cut > 120 ? cut : 200).trim()}...';
  }
  return s;
}

ExtractResult extractPlan(String reply, PlaceIndex index) {
  final dayRe = RegExp(r'^(?:day|يوم|اليوم)\s*(\d{1,2})(?!\d)\s*[:\-\u2013\u2014.)]*\s*(.*)$', caseSensitive: false);
  final boldRe = RegExp(r'\*\*(.+?)\*\*');
  final plan = Plan();
  PlanDay? current;
  var headings = 0;
  var sawDayHeading = false;

  for (final raw in westernDigits(reply).split(RegExp(r'\r?\n'))) {
    final text = _clean(raw);
    if (text.isEmpty) continue;

    final h = dayRe.firstMatch(text);
    if (h != null) {
      headings++;
      sawDayHeading = true;
      final prev = current;
      if (prev != null && prev.stops.isEmpty && plan.days.length == 1 && prev.title.isEmpty) {
        plan.days.clear(); // an empty lead-in day made by a list before the first heading
      }
      final d = PlanDay(int.parse(h.group(1)!), (h.group(2) ?? '').replaceAll(RegExp(r'^[:\-\u2013\u2014\s]+'), '').trim());
      plan.days.add(d);
      current = d;
      continue;
    }
    if (raw.trimLeft().startsWith('#') && plan.title == null && current == null) {
      plan.title = text;
      continue;
    }

    // Only list lines and labelled lines (Morning: ...) are stops; ordinary sentences such as a closing summary are not.
    final slot = _detectSlot(text);
    final labelled = RegExp(r'^[^:]{1,32}:').hasMatch(text) && slot != Slot.any;
    if (!_isBullet(raw) && !labelled) continue;

    // The places named on this line, in the order written: ones in Daleel's guide, and bold names that are not.
    final bolds = [for (final m in boldRe.allMatches(raw)) m.group(1)!];
    final entries = <Object>[];
    for (final b in bolds) {
      final inBold = index.find(b);
      if (inBold.isNotEmpty) {
        entries.addAll(inBold.map((m) => m.place));
      } else if (!_isLabel(b) && _looksLikePlaceName(b)) {
        entries.add(b.trim());
      }
    }
    // No bold place: read the whole sentence (the model does not always bold its stops).
    if (!entries.any((e) => e is PlaceFacts)) entries.addAll(index.find(text).map((m) => m.place));

    final note = _stopNote(text);
    // Stops listed before any "Day" heading (a plain list of places) go into one day.
    final PlanDay day;
    final cur = current;
    if (cur != null) {
      day = cur;
    } else {
      day = PlanDay(1, '');
      plan.days.add(day);
      current = day;
    }
    for (final e in entries) {
      if (e is PlaceFacts) {
        if (day.stops.any((s) => s.placeId == e.id)) continue;
        day.stops.add(PlanStop(facts: e, name: e.name, slot: slot, note: note));
      } else {
        final name = e as String;
        if (day.stops.any((s) => !s.inGuide && s.name.toLowerCase() == name.toLowerCase())) continue;
        day.stops.add(PlanStop(name: name, slot: slot, note: note));
      }
    }
  }

  final matched = plan.days.fold<int>(0, (a, d) => a + d.stops.where((s) => s.inGuide).length);
  final isPlan = (matched >= 2 && sawDayHeading) || matched >= 3;
  if (plan.days.isEmpty) plan.days.add(PlanDay(1, ''));
  recheck(plan);
  return ExtractResult(plan, isPlan, matched, headings);
}

// ---------------------------------------------------------------------------------------------
// Checking against the database facts
// ---------------------------------------------------------------------------------------------

/// Recomputes every warning from the facts. Call it after any edit (removing or moving a stop, people, budget).
void recheck(Plan plan) {
  plan.warnings.clear();
  final firstDayOf = <int, int>{};
  for (final day in plan.days) {
    day.warnings.clear();
    for (final stop in day.stops) {
      stop.warnings.clear();
      final f = stop.facts;
      if (f == null) {
        stop.warnings.add(const Warn(WarnKind.notInGuide));
        continue;
      }
      if (stop.slot != Slot.any && !f.is24h && f.openMinutes != null && f.closeMinutes != null) {
        final s = _slotStart[stop.slot]!, e = _slotEnd[stop.slot]!;
        if (f.openMinutes! > s + _slackMinutes) {
          stop.warnings.add(Warn(WarnKind.opensLater, clockText(f.openMinutes!)));
        } else if (f.closeMinutes! < e - _slackMinutes) {
          stop.warnings.add(Warn(WarnKind.closesEarlier, clockText(f.closeMinutes!)));
        }
      }
      final earlier = firstDayOf[f.id];
      if (earlier != null) {
        stop.warnings.add(Warn(WarnKind.repeated, 'Day $earlier'));
      } else {
        firstDayOf[f.id] = day.number;
      }
    }
    if (day.minutes > _longDayMinutes) {
      day.warnings.add(Warn(WarnKind.longDay, (day.minutes / 60).toStringAsFixed(1)));
    }
  }
  final budget = plan.budgetAed;
  if (budget != null && plan.total > budget) {
    plan.warnings.add(Warn(WarnKind.overBudget, (plan.total - budget).round().toString()));
  }
}

// ---------------------------------------------------------------------------------------------
// Editing (the itinerary page)
// ---------------------------------------------------------------------------------------------

void removeStop(Plan plan, int dayIndex, int stopIndex) {
  plan.days[dayIndex].stops.removeAt(stopIndex);
  recheck(plan);
}

/// Moves a stop up (-1) or down (+1) inside its day.
void moveStop(Plan plan, int dayIndex, int stopIndex, int delta) {
  final stops = plan.days[dayIndex].stops;
  final to = stopIndex + delta;
  if (to < 0 || to >= stops.length) return;
  final s = stops.removeAt(stopIndex);
  stops.insert(to, s);
  recheck(plan);
}

void setSlot(Plan plan, int dayIndex, int stopIndex, Slot slot) {
  plan.days[dayIndex].stops[stopIndex].slot = slot;
  recheck(plan);
}