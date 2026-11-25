// lib/rag/rag_core.dart
//
// The pure logic of the chatbot, ported from ready/05_rag_chat_mediapipe_embed.py: no Flutter and no
// model calls in this file, so it can be tested on its own (tool/rag_selftest.dart compares it with the
// Python script's real output).
//
// Settings were calibrated on EmbeddingGemma 2 (270m) scores: unrelated chunks score about 0.55 to 0.66,
// real questions about 0.69 to 0.86. A different embedder needs new numbers.

import 'dart:math' as math;

class RagSettings {
  const RagSettings({
    this.topK = 12,
    this.queriesMax = 3,
    this.minTop = 0.675,
    this.margin = 0.10,
    this.alwaysSearchMessage = true,
    this.historyUserTurns = 8,
    this.historyAnswerTurns = 2,
    this.historyAnswerChars = 1200,
    this.cardsMax = 6,
    this.maxPromptTokens = 2800,
  });

  /// Chunks put in the prompt per question (with several searches, split between them).
  final int topK;

  /// The model may write up to this many searches, one per topic.
  final int queriesMax;

  /// A search counts as relevant only if its best chunk scores at least this. Below it (a greeting,
  /// "What is love?", "Is that all?") the search adds nothing. Measured: real questions 0.688 to 0.858,
  /// the others 0.634 to 0.660.
  final double minTop;

  /// From a relevant search, only chunks within this distance of its best chunk are used.
  final double margin;

  /// The user's own words are always one of the searches (half of the slots).
  final bool alwaysSearchMessage;

  final int historyUserTurns;
  final int historyAnswerTurns;
  final int historyAnswerChars;

  /// At most this many extra place cards (hours, price) per question.
  final int cardsMax;

  /// Safety limit (rough tokens: words x 1.5). The engine's whole window is 4096 tokens, reply included;
  /// the lowest-scoring chunks are dropped if the prompt would be bigger.
  final int maxPromptTokens;
}

class Chunk {
  const Chunk(this.id, this.sourceType, this.text, this.vector, {this.sourceId = 0});
  final int id;
  final String sourceType; // attraction, event or general
  final String text;
  final List<double> vector;

  /// For an attraction card: the attraction's id in the database (opens its place screen). 0 otherwise.
  final int sourceId;
}

class Hit {
  const Hit(this.score, this.chunk);
  final double score;
  final Chunk chunk;
}

class Turn {
  const Turn(this.user, this.reply);
  final String user;
  final String reply;
}

// ---------------------------------------------------------------------------------------------
// The system prompt (PROMPT_MODE = "short" in the Python script)
// ---------------------------------------------------------------------------------------------

const String shortPrompt =
    "You are a friendly Al Ain tourism guide. Use the background facts for places, hours, prices and distances, "
    "and if they don't cover something, say you're not sure. Match the length to the question: a line or two for "
    "simple questions, and a fuller answer when the user asks about a place, a topic or its history, using the most "
    "interesting facts in the background. Stay on Al Ain and UAE travel. When asked for a plan, write it day by day "
    "within the user's budget and trip length, leaving out anything over budget.";

// ---------------------------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------------------------

double cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Every chunk scored against the query, best first (ties keep the original order).
List<Hit> rank(List<double> query, List<Chunk> chunks) {
  final scored = <MapEntry<int, Hit>>[
    for (var i = 0; i < chunks.length; i++) MapEntry(i, Hit(cosine(query, chunks[i].vector), chunks[i])),
  ];
  scored.sort((a, b) {
    final c = b.value.score.compareTo(a.value.score);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return [for (final e in scored) e.value];
}

// ---------------------------------------------------------------------------------------------
// Place cards: the database chunk with hours and price, pulled in next to the lore about the same place
// ---------------------------------------------------------------------------------------------

/// Maps each place's lower-case name to its database card. Cards look like
/// `Wadi Adventure (<Arabic name>) is a Family & Adventure attraction in Al Ain. Opening hours: ...`
Map<String, Chunk> buildCardIndex(List<Chunk> chunks) {
  final cards = <String, Chunk>{};
  for (final c in chunks) {
    final name = cardPlaceName(c.text);
    if (name != null) cards[name.toLowerCase()] = c;
  }
  return cards;
}

final _cardPattern = RegExp(r'^(.*?)\s+is an? .*?attraction in Al Ain\.');
final _arabicLetter = RegExp(r'[\u0600-\u06FF]');

/// The place's English name, as written on its card (null if the text is not a place card).
String? cardPlaceName(String text) {
  final m = _cardPattern.firstMatch(text);
  if (m == null) return null;
  var prefix = m.group(1)!;
  final a = _arabicLetter.firstMatch(prefix);
  if (a != null) {
    final cut = a.start >= 2 ? prefix.lastIndexOf(' (', a.start - 2) : -1;
    prefix = cut != -1 ? prefix.substring(0, cut) : prefix.substring(0, a.start);
  }
  return prefix.trim();
}

class CardResult {
  const CardResult(this.merged, this.names);
  final List<Hit> merged;
  final List<String> names;
}

String _heading(String text) {
  final i = text.indexOf(': ');
  return (i == -1 ? text : text.substring(0, i)).trim().toLowerCase();
}

/// For each retrieved lore chunk whose heading is a place name, make sure that place's card is in the results
/// with at least the same score. Matching is by name only. Returns the results best first, and the places whose
/// card was added or moved up.
CardResult attachCards(List<Hit> retrieved, Map<String, Chunk> cards, {int cardsMax = 6, double minScore = 0.0}) {
  final scores = <int, double>{for (final h in retrieved) h.chunk.id: h.score};
  final byId = <int, Chunk>{for (final h in retrieved) h.chunk.id: h.chunk};
  final wanted = <({double score, Chunk card, String name, int order})>[];
  final done = <int>{};
  for (final h in retrieved) {
    if (h.score < minScore) continue;
    final heading = _heading(h.chunk.text);
    for (final e in cards.entries) {
      final name = e.key, card = e.value;
      if (done.contains(card.id)) continue;
      if (heading == name || heading.startsWith('$name (') || name.startsWith('$heading (')) {
        done.add(card.id);
        if ((scores[card.id] ?? -1.0) < h.score) wanted.add((score: h.score, card: card, name: name, order: wanted.length));
        break;
      }
    }
  }
  wanted.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  final kept = wanted.take(cardsMax).toList();
  for (final w in kept) {
    scores[w.card.id] = w.score;
    byId[w.card.id] = w.card;
  }
  final order = scores.keys.toList();
  final sorted = <MapEntry<int, int>>[for (var i = 0; i < order.length; i++) MapEntry(i, order[i])]
    ..sort((a, b) {
      final c = scores[b.value]!.compareTo(scores[a.value]!);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return CardResult([for (final e in sorted) Hit(scores[e.value]!, byId[e.value]!)], [for (final w in kept) w.name]);
}

// ---------------------------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------------------------

String _cut(String s, int n) {
  if (s.length <= n) return s;
  // Do not cut between the two halves of an emoji (a surrogate pair): that leaves an invalid character.
  final cut = (n > 0 && (s.codeUnitAt(n) & 0xFC00) == 0xDC00) ? n - 1 : n;
  return s.substring(0, cut);
}

/// What the user has said so far (all short), plus the model's last couple of replies, shortened.
String buildHistoryText(List<Turn> history, RagSettings s) {
  if (history.isEmpty) return '';
  final us = history.length > s.historyUserTurns ? history.sublist(history.length - s.historyUserTurns) : history;
  final as = history.length > s.historyAnswerTurns ? history.sublist(history.length - s.historyAnswerTurns) : history;
  final said = us.map((t) => '- ${_cut(t.user, 250)}').join('\n');
  final last = as.map((t) => 'Assistant: ${_cut(t.reply, s.historyAnswerChars)}').join('\n');
  return 'What the user has said so far in this chat (oldest first):\n$said'
      '\n\nYour last replies, shortened:\n$last\n\nNew message from the user:\n';
}

/// The question, with the retrieved background after it. With nothing relevant, just the question.
String buildPrompt(String query, List<Hit> relevant, String historyText) {
  if (relevant.isEmpty) return historyText + query;
  final context = relevant.map((h) => '- ${h.chunk.text}').join('\n');
  return "$historyText$query\n\n[Background that may or may not be relevant to the question. "
      "Don't mention or quote it, and ignore it if it doesn't help: $context]";
}

/// The one short call that asks the model what to look up.
String searchPrompt(String historyText, String userInput, int queriesMax) {
  return '$historyText$userInput\n\n'
      'Write 1 to $queriesMax short search queries, one per line, to find the facts needed to answer the new message. '
      'Each query should be about ONE aspect of what the user is actually asking about, using the names of the places or topics in the conversation. '
      'If the user asks for more, or whether that is all, search for facts your earlier replies did not mention. '
      "Do not add topics the user did not ask about. Describe the facts you need, not budgets or dates, and do not use the words 'Al Ain' "
      '(everything here is about Al Ain). If the new message is only a greeting or thanks, write NONE. Output only the queries, one per line.';
}

String _stripChars(String s, String chars) {
  var start = 0, end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

/// Turns the model's reply into searches. NONE (a greeting) gives an empty list.
List<String> parseSearchQueries(String reply, int queriesMax) {
  final queries = <String>[];
  final lead = RegExp(r'^[\s\-\*\d\.\)]+');
  for (final raw in reply.trim().split(RegExp(r'\r?\n'))) {
    final line = _stripChars(raw.replaceFirst(lead, '').trim(), '"\'`*');
    if (line.isEmpty) continue;
    if (line.toUpperCase().startsWith('NONE')) return [];
    queries.add(_cut(line, 150));
  }
  return queries.length > queriesMax ? queries.sublist(0, queriesMax) : queries;
}

/// Rough token count (words x 1.5), the same estimate the Python script prints.
int estimateTokens(String text) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return (words * 1.5).round();
}