// lib/assistant/markdown_lite.dart
//
// Shows an answer with its **bold**, bullets, numbered lists, headings, tables, quotes and links (as text).
// The reading is done by markdown_lite_parse.dart (pure Dart, tested). No package is needed.

import 'package:flutter/material.dart';

import '../theme.dart';
import 'markdown_lite_parse.dart';

class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  List<InlineSpan> _spans(List<MdSpan> spans, {bool allBold = false}) => [
        for (final s in spans)
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: (s.bold || allBold) ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
              fontFamily: s.code ? 'monospace' : null,
            ),
          ),
      ];

  /// A table that fills the bubble when its columns fit, and scrolls sideways when they would be squeezed.
  Widget _table(MdBlock b, TextStyle base) {
    final small = base.copyWith(fontSize: (base.fontSize ?? 14) - 1);
    TableRow row(List<List<MdSpan>> cells, {bool header = false}) => TableRow(
          decoration: header ? BoxDecoration(color: parchment) : null,
          children: [
            for (final cell in cells)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text.rich(TextSpan(style: small, children: _spans(cell, allBold: header))),
              ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, box) {
          const minColumn = 110.0;
          final fits = box.maxWidth >= b.header.length * minColumn;
          final table = Table(
            border: TableBorder.all(color: duneLine),
            defaultColumnWidth: fits ? const FlexColumnWidth() : const FixedColumnWidth(minColumn),
            children: [row(b.header, header: true), for (final r in b.rows) row(r)],
          );
          return fits ? table : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final blocks = parseMarkdownLite(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in blocks)
          switch (b.type) {
            MdBlockType.paragraph => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text.rich(TextSpan(style: base, children: _spans(b.spans))),
              ),
            MdBlockType.heading => Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 2),
                child: Text.rich(TextSpan(
                  style: base.copyWith(fontSize: (base.fontSize ?? 14) + 1),
                  children: _spans(b.spans, allBold: true),
                )),
              ),
            MdBlockType.bullet || MdBlockType.numbered => Padding(
                padding: EdgeInsetsDirectional.only(bottom: 4, start: 16.0 * b.level),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(b.type == MdBlockType.bullet ? '\u2022' : '${b.number}.', style: base),
                    ),
                    Expanded(child: Text.rich(TextSpan(style: base, children: _spans(b.spans)))),
                  ],
                ),
              ),
            MdBlockType.quote => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: duneLine, width: 3))),
                  child: Text.rich(TextSpan(style: base.copyWith(fontStyle: FontStyle.italic), children: _spans(b.spans))),
                ),
              ),
            MdBlockType.table => _table(b, base),
            MdBlockType.rule => const Divider(height: 16),
          },
      ],
    );
  }
}
