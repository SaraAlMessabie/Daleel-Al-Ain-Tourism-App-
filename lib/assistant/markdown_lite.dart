// lib/assistant/markdown_lite.dart
//
// Shows an answer with its **bold**, bullets, numbered lists and headings. The reading is done by
// markdown_lite_parse.dart (pure Dart, tested). No package is needed.

import 'package:flutter/material.dart';

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
            ),
          ),
      ];

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
                padding: const EdgeInsets.only(bottom: 4),
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
            MdBlockType.rule => const Divider(height: 16),
          },
      ],
    );
  }
}