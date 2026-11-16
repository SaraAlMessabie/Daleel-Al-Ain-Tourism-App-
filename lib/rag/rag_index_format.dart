// lib/rag/rag_index_format.dart
//
// Reads the knowledge base the app ships: assets/data/rag_index.json, made by ready/10_make_rag_asset.py.
// One file with every chunk's text and its vector (float32 numbers, packed as base64), so the app never
// touches its own database for the assistant and users' saved data is never at risk.
//
// {"format": 1, "embedder": "embeddinggemma-2-text-270m@9be6e8b9", "dim": 768,
//  "chunks": [{"id": 1, "type": "attraction", "source_id": 7, "text": "...", "vec": "<base64>"}, ...]}

import 'dart:convert';
import 'dart:typed_data';

import 'rag_core.dart';

class RagIndex {
  const RagIndex(this.embedder, this.dim, this.chunks);

  /// Which embedder made the vectors. Questions must be embedded with the same one.
  final String embedder;
  final int dim;
  final List<Chunk> chunks;
}

RagIndex decodeRagIndex(String jsonText) {
  final root = jsonDecode(jsonText) as Map<String, dynamic>;
  if (root['format'] != 1) {
    throw FormatException('unknown rag_index format: ${root['format']}');
  }
  final dim = (root['dim'] as num).toInt();
  final chunks = <Chunk>[];
  for (final c in root['chunks'] as List) {
    final bytes = base64Decode(c['vec'] as String);
    if (bytes.length != dim * 4) {
      throw FormatException('chunk ${c['id']}: ${bytes.length} bytes, expected ${dim * 4}');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    chunks.add(Chunk(
      (c['id'] as num).toInt(),
      c['type'] as String,
      c['text'] as String,
      [for (var i = 0; i < dim; i++) data.getFloat32(i * 4, Endian.little)],
      sourceId: ((c['source_id'] ?? 0) as num).toInt(),
    ));
  }
  if (chunks.isEmpty) throw const FormatException('rag_index has no chunks');
  return RagIndex(root['embedder'] as String, dim, chunks);
}