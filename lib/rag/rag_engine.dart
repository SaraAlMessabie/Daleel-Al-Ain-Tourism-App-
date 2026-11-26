// lib/rag/rag_engine.dart
//
// One chat turn, ported from main() in ready/05_rag_chat_mediapipe_embed.py, with the relevance rule
// calibrated for the on-device embedder. Pure Dart: the embedder and the language model come in through the
// two small interfaces below (lib/rag/edge_ports.dart connects them to flutter_edge_ai), so the whole turn can
// be tested with fakes.

import 'dart:math' as math;

import 'rag_core.dart';

abstract class EmbedderPort {
  /// The vector of a question (the embedder's "retrieval query" kind).
  Future<List<double>> embedQuery(String text);
}

abstract class LlmPort {
  /// A short one-off call with no system prompt (used to write the searches).
  Future<String> complete(String prompt, {int? maxOutputTokens});

  /// The answer, streamed word by word, with the system prompt.
  Stream<String> answer(String prompt, {required String systemPrompt});
}

/// A place named in the reply, with the id that opens its screen in the app.
class PlaceRef {
  const PlaceRef(this.attractionId, this.name, [this.nameAr]);
  final int attractionId;
  final String name;

  /// The Arabic name from the place's card, when it has one.
  final String? nameAr;
}

class TurnResult {
  TurnResult({
    required this.places,
    required this.reply,
    required this.prompt,
    required this.queries,
    required this.messageSearchRelevant,
    required this.skippedSearch,
    required this.hits,
    required this.cardsAttached,
    required this.droppedForSize,
    required this.promptTokens,
    required this.searchMs,
    required this.readMs,
    required this.writeMs,
  });

  final String reply;
  final String prompt;

  /// Places whose card was in the prompt and whose name the reply uses (at most 4), for "open this place" buttons.
  final List<PlaceRef> places;

  /// The searches the model wrote (empty: NONE, or none were asked for).
  final List<String> queries;

  /// Whether the user's own words matched the knowledge base well enough (best score at least minTop).
  final bool messageSearchRelevant;

  /// True when the first message matched nothing (a greeting or off-topic): no searches and no extra model call.
  final bool skippedSearch;

  /// The chunks in the prompt, best first, place cards included.
  final List<Hit> hits;
  final List<String> cardsAttached;
  final int droppedForSize;
  final int promptTokens;
  final int searchMs;
  final int readMs;
  final int writeMs;

  int get totalMs => searchMs + readMs + writeMs;
  int get words => reply.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

class RagEngine {
  RagEngine({
    required List<Chunk> chunks,
    required this.embedder,
    required this.llm,
    this.settings = const RagSettings(),
    this.systemPrompt = shortPrompt,
  })  : _chunks = chunks,
        _cards = buildCardIndex(chunks) {
    for (final e in _cards.entries) {
      final name = cardPlaceName(e.value.text);
      if (name != null) _cardNames[e.value.id] = name;
      final ar = cardPlaceNameAr(e.value.text);
      if (ar != null && ar.isNotEmpty) _cardNamesAr[e.value.id] = ar;
    }
  }

  final EmbedderPort embedder;
  final LlmPort llm;
  final RagSettings settings;
  final String systemPrompt;
  final List<Chunk> _chunks;
  final Map<String, Chunk> _cards;
  final Map<int, String> _cardNames = {}; // card chunk id -> the place's name as written on the card
  final Map<int, String> _cardNamesAr = {}; // card chunk id -> the place's Arabic name on the card
  final List<Turn> history = [];

  int get chunkCount => _chunks.length;
  int get cardCount => _cards.length;

  void reset() => history.clear();

  /// [userContext] is a short note about the visitor (interests, budget, travel style) and today's date. It goes
  /// into the answer prompt only, not into the searches, so it never changes what is retrieved.
  Future<TurnResult> ask(String userInput, {void Function(String token)? onToken, String? userContext}) async {
    final s = settings;
    final clock = Stopwatch()..start();
    final historyText = buildHistoryText(history, s);

    // 1. The user's own words.
    final msgRanked = rank(await embedder.embedQuery(userInput), _chunks);
    final msgRelevant = msgRanked.isNotEmpty && msgRanked.first.score >= s.minTop;

    // 2. The model writes searches. Not for a first message that matches nothing (a greeting or off-topic):
    //    that saves a whole model call. In a running chat it always runs, because a follow-up such as
    //    "Is that all?" means nothing without the conversation.
    final skipped = history.isEmpty && !msgRelevant;
    var queries = <String>[];
    if (!skipped) {
      try {
        final reply = await llm.complete(searchPrompt(historyText, userInput, s.queriesMax), maxOutputTokens: 120);
        queries = parseSearchQueries(reply, s.queriesMax);
      } catch (_) {
        queries = []; // the user's own words are still searched below
      }
    }

    // 3. Gather chunks. Each search is judged on its own: it counts only if its best chunk is relevant enough,
    //    and then only chunks close to its best are used.
    final best = <int, Hit>{};
    final relevantRankings = <List<Hit>>[];
    void take(List<Hit> ranked, int n) {
      if (ranked.isEmpty || ranked.first.score < s.minTop) return;
      relevantRankings.add(ranked);
      final floor = ranked.first.score - s.margin;
      var taken = 0;
      for (final h in ranked) {
        if (taken >= n || h.score < floor) break;
        final prev = best[h.chunk.id];
        if (prev == null || h.score > prev.score) best[h.chunk.id] = h;
        taken++;
      }
    }

    final own = s.alwaysSearchMessage ? s.topK ~/ 2 : 0;
    if (own > 0) take(msgRanked, own);
    if (queries.isNotEmpty) {
      final share = math.max(2, (s.topK - own) ~/ queries.length);
      for (final q in queries) {
        take(rank(await embedder.embedQuery(q), _chunks), share);
      }
    }
    // The searches overlapped (all about one place): top up from the best relevant search, within its margin.
    if (relevantRankings.isNotEmpty && best.length < s.topK) {
      final source = relevantRankings.first;
      final floor = source.first.score - s.margin;
      for (final h in source) {
        if (best.length >= s.topK || h.score < floor) break;
        best.putIfAbsent(h.chunk.id, () => h);
      }
    }
    final order = best.values.toList();
    final stable = <MapEntry<int, Hit>>[for (var i = 0; i < order.length; i++) MapEntry(i, order[i])]
      ..sort((a, b) {
        final c = b.value.score.compareTo(a.value.score);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    var retrieved = [for (final e in stable) e.value];
    if (retrieved.length > s.topK) retrieved = retrieved.sublist(0, s.topK);

    // 4. Place cards (hours, price) for the places the lore chunks are about.
    var cardsAttached = <String>[];
    if (retrieved.isNotEmpty) {
      final withCards = attachCards(retrieved, _cards, cardsMax: s.cardsMax);
      retrieved = withCards.merged;
      cardsAttached = withCards.names;
    }

    // 5. The prompt. If it would not fit the engine's window, the lowest-scoring chunks go.
    var shown = List<Hit>.from(retrieved);
    final question = (userContext == null || userContext.trim().isEmpty) ? userInput : '$userContext\n\n$userInput';
    var prompt = buildPrompt(question, shown, historyText);
    final systemTokens = estimateTokens(systemPrompt);
    var dropped = 0;
    while (estimateTokens(prompt) + systemTokens > s.maxPromptTokens && shown.length > 3) {
      shown.removeLast();
      dropped++;
      prompt = buildPrompt(question, shown, historyText);
    }
    final searchMs = clock.elapsedMilliseconds;

    // 6. The answer, streamed.
    final reply = StringBuffer();
    final answerClock = Stopwatch()..start();
    int? firstMs;
    await for (final token in llm.answer(prompt, systemPrompt: systemPrompt)) {
      firstMs ??= answerClock.elapsedMilliseconds;
      reply.write(token);
      onToken?.call(token);
    }
    final totalAnswerMs = answerClock.elapsedMilliseconds;
    final readMs = firstMs ?? totalAnswerMs;
    history.add(Turn(userInput, reply.toString()));

    final lowReply = reply.toString().toLowerCase();
    final places = <PlaceRef>[];
    for (final h in shown) {
      final name = _cardNames[h.chunk.id];
      if (name == null || h.chunk.sourceId <= 0 || places.length >= 4) continue;
      final ar = _cardNamesAr[h.chunk.id];
      // Arabic answers name places in Arabic, so match the Arabic name too.
      final named = lowReply.contains(name.toLowerCase()) || (ar != null && lowReply.contains(ar));
      if (named && places.every((p) => p.attractionId != h.chunk.sourceId)) {
        places.add(PlaceRef(h.chunk.sourceId, name, ar));
      }
    }

    return TurnResult(
      places: places,
      reply: reply.toString(),
      prompt: prompt,
      queries: queries,
      messageSearchRelevant: msgRelevant,
      skippedSearch: skipped,
      hits: shown,
      cardsAttached: cardsAttached,
      droppedForSize: dropped,
      promptTokens: estimateTokens(prompt) + systemTokens,
      searchMs: searchMs,
      readMs: readMs,
      writeMs: math.max(0, totalAnswerMs - readMs),
    );
  }
}