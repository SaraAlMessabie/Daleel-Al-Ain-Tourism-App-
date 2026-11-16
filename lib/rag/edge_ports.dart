// lib/rag/edge_ports.dart
//
// Connects the chat engine to the real on-device models. Only calls already proven in the test pages
// (getActiveEmbedder().embed, getActiveModel, createChat, addQueryChunk, generateChatResponseAsync), plus
// createChat(systemInstruction:, maxOutputTokens:), which the package's API documentation lists.

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'rag_engine.dart';

class EdgeEmbedderPort implements EmbedderPort {
  @override
  Future<List<double>> embedQuery(String text) async {
    final embedder = await FlutterEdgeAi.getActiveEmbedder();
    return List<double>.from(
      await embedder.embed(EmbeddingInput.text(text), taskType: TaskType.retrievalQuery),
    );
  }
}

class EdgeLlmPort implements LlmPort {
  EdgeLlmPort({this.maxTokens = 4096});

  /// The model's whole window: prompt, history and answer together.
  final int maxTokens;

  @override
  Future<String> complete(String prompt, {int? maxOutputTokens}) async {
    final model = await FlutterEdgeAi.getActiveModel(maxTokens: maxTokens);
    final chat = await model.createChat(maxOutputTokens: maxOutputTokens);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final out = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) out.write(response.token);
    }
    return out.toString();
  }

  @override
  Stream<String> answer(String prompt, {required String systemPrompt}) async* {
    final model = await FlutterEdgeAi.getActiveModel(maxTokens: maxTokens);
    // A fresh chat for every question, like the Python script: old background never fills the window.
    final chat = await model.createChat(systemInstruction: systemPrompt);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) yield response.token;
    }
  }
}
