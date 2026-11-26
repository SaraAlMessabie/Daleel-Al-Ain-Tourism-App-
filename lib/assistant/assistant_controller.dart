// lib/assistant/assistant_controller.dart
//
// Everything the Assistant tab needs, apart from drawing it: is the assistant installed, downloading it,
// starting it, and the chat itself. The search and answering logic is in lib/rag/ (pure Dart, tested).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import '../data.dart' show loadAttractions;
import '../itinerary/itinerary_core.dart' as itin;
import '../rag/edge_ports.dart';
import '../rag/rag_engine.dart';
import '../rag/rag_index_format.dart';

enum AssistantPhase { starting, needsSetup, downloading, ready, failed }

/// Set by main() when the on-device AI engines started. If they did not, this phone cannot run the assistant,
/// so offering the 2.6 GB download would only end in a failure.
bool assistantEnginesStarted = false;

enum AssistantFailure { start, download, unsupported }

class ChatMessage {
  ChatMessage(this.fromUser, this.text);
  final bool fromUser;
  String text;
  List<PlaceRef> places = const [];

  /// Set when the answer reads like a plan: the itinerary that can be made from it.
  itin.Plan? plan;

  /// The id of that itinerary once it has been saved, so saving again updates it instead of making a copy.
  int? savedItineraryId;
  bool failed = false;
}

// The search model (EmbeddingGemma 2, 165 MB, not gated). The knowledge base was embedded with this exact
// one (see assets/data/rag_index.json); a different embedder would give meaningless scores.
const _embedderLabelPrefix = 'embeddinggemma-2-text-270m';
const _embedderUrl = 'https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/resolve/'
    '9be6e8b90982095dc05c2bd162e4b954ee4dbac7/embeddinggemma-2-text-270m.litertlm';
const _indexAsset = 'assets/data/rag_index.json';

class AssistantController extends ChangeNotifier {
  AssistantPhase phase = AssistantPhase.starting;
  AssistantFailure failure = AssistantFailure.start;
  final List<ChatMessage> messages = [];
  bool answering = false;

  /// 1 = downloading the search model, 2 = downloading the language model.
  int downloadStep = 1;

  /// 0 to 1 while the language model downloads, null when not known.
  double? progress;

  RagEngine? _engine;
  itin.PlaceIndex? _placeIndex;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setPhase(AssistantPhase p) {
    phase = p;
    _notify();
  }

  /// Loads everything. If the two models have never been installed, asks for the one-time download instead.
  Future<void> start({bool afterInstall = false}) async {
    if (!assistantEnginesStarted) {
      failure = AssistantFailure.unsupported;
      _setPhase(AssistantPhase.failed);
      return;
    }
    _setPhase(AssistantPhase.starting);
    try {
      await FlutterEdgeAi.getActiveEmbedder();
      await FlutterEdgeAi.getActiveModel(maxTokens: 4096);
    } catch (e, st) {
      debugPrint('Assistant: models not available: $e\n$st');
      if (afterInstall) {
        failure = AssistantFailure.start;
        _setPhase(AssistantPhase.failed);
      } else {
        _setPhase(AssistantPhase.needsSetup);
      }
      return;
    }
    try {
      final index = decodeRagIndex(await rootBundle.loadString(_indexAsset));
      if (!index.embedder.startsWith(_embedderLabelPrefix)) {
        throw StateError('the knowledge base was made with ${index.embedder}, the app expects $_embedderLabelPrefix');
      }
      final engine = RagEngine(chunks: index.chunks, embedder: EdgeEmbedderPort(), llm: EdgeLlmPort());
      // Reading a prompt for the first time is slow; do it now, while the "starting" screen is up.
      await engine.embedder.embedQuery('warm up');
      await engine.llm.complete('Reply with one word: ready', maxOutputTokens: 8);
      _engine = engine;
      try {
        // Daleel's own places, so a plan in an answer can be turned into an itinerary. If this fails the chat still works.
        _placeIndex = itin.PlaceIndex([for (final a in await loadAttractions()) itin.PlaceFacts.fromRow(a.row)]);
      } catch (e, st) {
        debugPrint('Assistant: itinerary places not loaded: $e\n$st');
      }
      _setPhase(AssistantPhase.ready);
    } catch (e, st) {
      debugPrint('Assistant: could not start: $e\n$st');
      failure = AssistantFailure.start;
      _setPhase(AssistantPhase.failed);
    }
  }

  /// The one-time download: the search model, then the language model.
  Future<void> install() async {
    if (phase == AssistantPhase.downloading) return;
    downloadStep = 1;
    progress = null;
    _setPhase(AssistantPhase.downloading);
    try {
      await FlutterEdgeAi.installEmbedder().modelFromNetwork(_embedderUrl).install();
      downloadStep = 2;
      progress = 0;
      _notify();
      await FlutterEdgeAi.installModelFromCatalog(LiteRtLmModels.gemma4E2bIt.generic).withProgress((p) {
        progress = ((double.tryParse('$p') ?? 0) / 100).clamp(0.0, 1.0);
        _notify();
      }).install();
    } catch (e, st) {
      debugPrint('Assistant: download failed: $e\n$st');
      failure = AssistantFailure.download;
      _setPhase(AssistantPhase.failed);
      return;
    }
    await start(afterInstall: true);
  }

  /// [userContext]: a short note about the visitor and today's date (see RagEngine.ask).
  Future<void> send(String text, {String? userContext}) async {
    final engine = _engine;
    final question = text.trim();
    if (engine == null || question.isEmpty || answering) return;
    final reply = ChatMessage(false, '');
    messages
      ..add(ChatMessage(true, question))
      ..add(reply);
    answering = true;
    _notify();
    try {
      final result = await engine.ask(question, userContext: userContext, onToken: (token) {
        reply.text += token;
        _notify();
      });
      reply.places = result.places;
      final index = _placeIndex;
      if (index != null) {
        final found = itin.extractPlan(reply.text, index);
        if (found.isPlan) reply.plan = found.plan;
      }
    } catch (e, st) {
      debugPrint('Assistant: answer failed: $e\n$st');
      reply.failed = true;
    }
    answering = false;
    _notify();
  }

  void newChat() {
    if (answering) return;
    _engine?.reset();
    messages.clear();
    _notify();
  }
}