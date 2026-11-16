// lib/assistant/markdown_lite_parse.dart   (pure Dart, tested by tool/rag_selftest.dart)
//
// A small Markdown reader for the assistant's answers: headings, bullets, numbered lists, **bold**, *italic*.
// Gemma writes mostly paragraphs, bullet lists and bold names, so this is enough, and it needs no package.
// Anything it does not understand (tables, code, links) is shown as plain text, never dropped.

enum MdBlockType { paragraph, heading, bullet, numbered, rule }

class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold;
  final bool italic;
}

class MdBlock {
  const MdBlock(this.type, this.spans, {this.number = 0});
  final MdBlockType type;
  final List<MdSpan> spans;
  final int number; // for numbered items

  String get plain => spans.map((s) => s.text).join();
}

/// **bold** and *italic* inside one line. An unclosed marker (a reply still being written) stays as typed.
List<MdSpan> parseInline(String line) {
  final spans = <MdSpan>[];
  final buffer = StringBuffer();
  var i = 0;
  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(MdSpan(buffer.toString()));
      buffer.clear();
    }
  }

  while (i < line.length) {
    if (line.startsWith('**', i)) {
      final end = line.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        spans.add(MdSpan(line.substring(i + 2, end), bold: true));
        i = end + 2;
        continue;
      }
    } else if (line[i] == '*' && i + 1 < line.length && line[i + 1] != ' ' && line[i + 1] != '*') {
      final end = line.indexOf('*', i + 1);
      if (end > i + 1 && line[end - 1] != ' ') {
        flush();
        spans.add(MdSpan(line.substring(i + 1, end), italic: true));
        i = end + 1;
        continue;
      }
    }
    buffer.write(line[i]);
    i++;
  }
  flush();
  return spans.isEmpty ? [const MdSpan('')] : spans;
}

List<MdBlock> parseMarkdownLite(String text) {
  final blocks = <MdBlock>[];
  final paragraph = <String>[];
  void endParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(MdBlock(MdBlockType.paragraph, parseInline(paragraph.join(' '))));
      paragraph.clear();
    }
  }

  final heading = RegExp(r'^#{1,6}\s+(.*)$');
  final bullet = RegExp(r'^\s*[-*\u2022]\s+(.*)$');
  final numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$');
  final rule = RegExp(r'^\s*(-{3,}|_{3,}|\*{3,})\s*$');

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      endParagraph();
      continue;
    }
    if (rule.hasMatch(line)) {
      endParagraph();
      blocks.add(const MdBlock(MdBlockType.rule, []));
      continue;
    }
    final h = heading.firstMatch(line);
    if (h != null) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.heading, parseInline(h.group(1)!.trim())));
      continue;
    }
    final b = bullet.firstMatch(line);
    // "**Bold** text" starts with * but is not a bullet: a bullet has a space after the marker.
    if (b != null && !line.trimLeft().startsWith('**')) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.bullet, parseInline(b.group(1)!.trim())));
      continue;
    }
    final n = numbered.firstMatch(line);
    if (n != null) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.numbered, parseInline(n.group(2)!.trim()), number: int.parse(n.group(1)!)));
      continue;
    }
    paragraph.add(line.trim());
  }
  endParagraph();
  return blocks;
}

/// True if the text is mostly Arabic, so the bubble can be laid out right to left.
bool looksArabic(String text) {
  var arabic = 0, latin = 0;
  for (final r in text.runes) {
    if (r >= 0x0600 && r <= 0x06FF) {
      arabic++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      latin++;
    }
  }
  return arabic > latin;
}