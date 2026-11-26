// Unit tests for the app's own rules (no phone, no models needed): Explore ranking, search, "open now",
// the assistant's prompt size and visitor note, Arabic place names, and reading Arabic plans.

import 'package:flutter_test/flutter_test.dart';

import 'package:daleel/app_state.dart';
import 'package:daleel/assistant/assistant_screen.dart' show visitorNote;
import 'package:daleel/data.dart';
import 'package:daleel/itinerary/itinerary_core.dart';
import 'package:daleel/rag/rag_core.dart';

Attraction place(int id, {List<int> tags = const [], double price = 0, double popularity = 50,
    String? open, String? close, String closed = 'None', int is24 = 0}) {
  return Attraction({
    'attraction_id': id,
    'name_en': 'Place $id',
    'entry_price_aed': price,
    'popularity_score': popularity,
    'open_time': open,
    'close_time': close,
    'closed_days': closed,
    'is_24_hours': is24,
  }, tags.toSet());
}

void main() {
  group('Explore ranking', () {
    test('matching interests come first, popularity only breaks ties', () {
      final ranked = rankAttractions(
        [place(1, popularity: 95), place(2, tags: [13], popularity: 10)],
        {13},
        null,
        null,
      );
      expect(ranked.first.id, 2);
    });

    test('travel style changes the order', () {
      final zoo = place(1, tags: [17, 28]); // wildlife, theme park
      final viewpoint = place(2, tags: [16, 19]); // scenic views, relaxation
      expect(rankAttractions([zoo, viewpoint], {}, 'family', null).first.id, 1);
      expect(rankAttractions([zoo, viewpoint], {}, 'couple', null).first.id, 2);
    });

    test('places over the budget go to the bottom', () {
      final ranked = rankAttractions(
        [place(1, tags: [13], price: 150), place(2, price: 0)],
        {13},
        null,
        50,
      );
      expect(ranked.last.id, 1);
    });
  });

  group('Search', () {
    test('Arabic spelling variants match', () {
      expect(searchKey('أبو ظبي'), searchKey('ابو ظبي'));
      expect(searchKey('واحة العين').contains(searchKey('واحه')), isTrue);
      expect(searchKey('Al Ain OASIS').contains('oasis'), isTrue);
    });
  });

  group('Open now', () {
    final monday10 = DateTime(2026, 11, 23, 10, 0); // a Monday
    final friday10 = DateTime(2026, 11, 27, 10, 0); // a Friday
    test('inside and outside the opening times', () {
      final p = place(1, open: '09:00', close: '17:00');
      expect(p.openAt(monday10), isTrue);
      expect(p.openAt(DateTime(2026, 11, 23, 18, 0)), isFalse);
    });
    test('unknown when there are no times', () {
      expect(place(1).openAt(monday10), isNull);
    });
    test('a Friday note makes Friday unknown but not other days', () {
      final p = place(1, open: '09:00', close: '17:00', closed: 'Friday until 3:00 PM');
      expect(p.openAt(friday10), isNull);
      expect(p.openAt(monday10), isTrue);
    });
    test('24 hours is always open', () {
      expect(place(1, is24: 1).openAt(DateTime(2026, 11, 23, 3, 0)), isTrue);
    });
  });

  group('Assistant', () {
    test('Arabic words count as more tokens than English ones', () {
      expect(estimateTokens('one two'), 3);
      expect(estimateTokens('واحة العين'), 6);
    });

    test('the Arabic name is read from a place card', () {
      const card = 'Al Ain Oasis (واحة العين) is a Heritage & Culture attraction in Al Ain. Opening hours: daily.';
      expect(cardPlaceName(card), 'Al Ain Oasis');
      expect(cardPlaceNameAr(card), 'واحة العين');
    });

    test('NONE means no searches', () {
      expect(parseSearchQueries('NONE', 3), isEmpty);
      expect(parseSearchQueries('1. Jebel Hafeet road\n2. Al Ain Zoo hours', 3).length, 2);
    });

    test('the visitor note carries the quiz answers and the date', () {
      final s = AppState()
        ..travelStyle = 'family'
        ..budget = 50
        ..tagIds = {13, 25};
      final note = visitorNote(s, DateTime(2026, 11, 26, 13, 5));
      expect(note, contains('travelling as a family'));
      expect(note, contains('History & heritage'));
      expect(note, contains('50 AED'));
      expect(note, contains('Thursday 26 November 2026, 13:05'));
    });
  });

  group('Itineraries', () {
    final index = PlaceIndex(const [
      PlaceFacts(id: 2, name: 'Al Jahili Fort', nameAr: 'حصن الجاهلي'),
      PlaceFacts(id: 1, name: 'Al Ain Oasis', nameAr: 'واحة العين'),
    ]);

    test('an Arabic plan with Arabic-Indic day numbers becomes an itinerary', () {
      const reply = 'اليوم ١\n- الصباح: **حصن الجاهلي**\n- العصر: **واحه العين**';
      final r = extractPlan(reply, index);
      expect(r.isPlan, isTrue);
      expect(r.plan.days.first.number, 1);
      expect([for (final s in r.plan.days.first.stops) s.placeId], [2, 1]);
    });

    test('Arabic-Indic digits are converted', () {
      expect(westernDigits('اليوم ٢'), 'اليوم 2');
    });
  });
}
