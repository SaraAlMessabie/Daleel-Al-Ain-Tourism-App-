// lib/rag/chunk_loader_json.dart   (desktop test app only: reads files from the PC)
//
// Loads the chunks the way the Index builder wrote them: chunks.json (the texts, from
// ready/08_export_chunks.py) and chunks_v2.json (the vectors, from the Index builder page).
// The phone version will read the same chunks from the database instead (rag_chunks.embedding_v2).

import 'dart:convert';
import 'dart:io';

import 'rag_core.dart';

Future<List<Chunk>> loadChunksFromJson(String dir) async {
  final sep = Platform.pathSeparator;
  final texts = jsonDecode(await File('$dir${sep}chunks.json').readAsString()) as List;
  final v2 = jsonDecode(await File('$dir${sep}chunks_v2.json').readAsString()) as Map<String, dynamic>;
  final vectors = <int, List<double>>{};
  final vectorText = <int, String>{};
  for (final c in v2['chunks'] as List) {
    final id = (c['chunk_id'] as num).toInt();
    vectors[id] = [for (final x in c['vector'] as List) (x as num).toDouble()];
    vectorText[id] = c['text'] as String;
  }
  final chunks = <Chunk>[];
  for (final t in texts) {
    final id = (t['chunk_id'] as num).toInt();
    final v = vectors[id];
    if (v == null) {
      throw StateError('chunk $id has no vector in chunks_v2.json: run the Index builder again');
    }
    if (vectorText[id] != t['text']) {
      throw StateError('chunk $id: the text differs between chunks.json and chunks_v2.json: export and embed again');
    }
    chunks.add(Chunk(id, t['source_type'] as String, t['text'] as String, v));
  }
  if (chunks.isEmpty) throw StateError('chunks.json is empty');
  return chunks;
}
