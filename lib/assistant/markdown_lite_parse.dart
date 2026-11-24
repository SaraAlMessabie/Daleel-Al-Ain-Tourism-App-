// lib/assistant/markdown_lite_parse.dart   (pure Dart, tested by tool/rag_selftest.dart)
//
// A small Markdown reader for the assistant's answers: headings, bullets (also nested), numbered lists, tables,
// quotes, rules, and inline **bold**, *italic*, `code` and [links](text only). No package is needed.
// Anything it does not understand is shown as plain text, never dropped.

enum MdBlockType { paragraph, heading, bullet, numbered, rule, table, quote }

class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false, this.code = false});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

class MdBlock {
  const MdBlock(
    this.type,
    this.spans, {
    this.number = 0,
    this.level = 0,
    this.header = const [],
    this.rows = const [],
  });
  final MdBlockType type;
  final List<MdSpan> spans;
  final int number; // for numbered items
  final int level; // nesting of a bullet or numbered item, 0 to 2

  /// For a table: the header cells, and the rows below it (every row has as many cells as the header).
  final List<List<MdSpan>> header;
  final List<List<List<MdSpan>>> rows;

  String get plain => spans.map((s) => s.text).join();
}

/// **bold**, *italic*, `code` and [label](link) inside one line. An unclosed marker (a reply still being
/// written) stays as typed. A link shows only its label.
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
    } else if (line[i] == '`') {
      final end = line.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        spans.add(MdSpan(line.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    } else if (line[i] == '[') {
      final close = line.indexOf('](', i + 1);
      final paren = close == -1 ? -1 : line.indexOf(')', close + 2);
      if (close > i + 1 && paren > close) {
        flush();
        spans.add(MdSpan(line.substring(i + 1, close)));
        i = paren + 1;
        continue;
      }
    }
    buffer.write(line[i]);
    i++;
  }
  flush();
  return spans.isEmpty ? [const MdSpan('')] : spans;
}

final _separator = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');

/// A table's separator row: dashes (and colons) between pipes, such as |---|:---:|. It must contain a pipe, so
/// a plain --- stays a horizontal rule.
bool _isSeparator(String line) => line.contains('|') && _separator.hasMatch(line);

List<List<MdSpan>> _cells(String line) {
  var t = line.trim().replaceAll(r'\|', '\u0001');
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  return [
    for (final c in t.split('|'))
      parseInline(c.replaceAll('\u0001', '|').trim().replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')),
  ];
}

int _levelOf(String raw) {
  final indent = raw.length - raw.trimLeft().length;
  return indent == 0 ? 0 : (indent < 6 ? 1 : 2);
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
  final quote = RegExp(r'^\s*>\s?(.*)$');

  final lines = text.split(RegExp(r'\r?\n'));
  var i = 0;
  while (i < lines.length) {
    final raw = lines[i].trimRight();
    i++;
    if (raw.trim().isEmpty) {
      endParagraph();
      continue;
    }
    // A table: a line with pipes, then a separator row, then rows until a line without pipes.
    if (raw.contains('|') && i < lines.length && _isSeparator(lines[i])) {
      endParagraph();
      final header = _cells(raw);
      final rows = <List<List<MdSpan>>>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty && lines[j].contains('|')) {
        final cells = _cells(lines[j]);
        rows.add([
          for (var c = 0; c < header.length; c++) c < cells.length ? cells[c] : [const MdSpan('')],
        ]);
        j++;
      }
      blocks.add(MdBlock(MdBlockType.table, const [], header: header, rows: rows));
      i = j;
      continue;
    }
    if (rule.hasMatch(raw)) {
      endParagraph();
      blocks.add(const MdBlock(MdBlockType.rule, []));
      continue;
    }
    final h = heading.firstMatch(raw);
    if (h != null) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.heading, parseInline(h.group(1)!.trim())));
      continue;
    }
    final q = quote.firstMatch(raw);
    if (q != null) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.quote, parseInline(q.group(1)!.trim())));
      continue;
    }
    final b = bullet.firstMatch(raw);
    // "**Bold** text" starts with * but is not a bullet: a bullet has a space after the marker.
    if (b != null && !raw.trimLeft().startsWith('**')) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.bullet, parseInline(b.group(1)!.trim()), level: _levelOf(raw)));
      continue;
    }
    final n = numbered.firstMatch(raw);
    if (n != null) {
      endParagraph();
      blocks.add(MdBlock(MdBlockType.numbered, parseInline(n.group(2)!.trim()), number: int.parse(n.group(1)!), level: _levelOf(raw)));
      continue;
    }
    paragraph.add(raw.trim());
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
