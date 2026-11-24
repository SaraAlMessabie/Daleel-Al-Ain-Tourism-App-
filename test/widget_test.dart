// Replaces the default counter test from the Flutter template, which referenced a class (MyApp) that does not exist.
// These two tests need no phone or models: they check the chat's text reading.

import 'package:flutter_test/flutter_test.dart';

import 'package:daleel/assistant/markdown_lite_parse.dart';

void main() {
  test('**bold** text is read as bold', () {
    final spans = parseInline('A **bold** word');
    expect(spans.any((s) => s.bold && s.text == 'bold'), isTrue);
  });

  test('Arabic text is recognised, English is not', () {
    expect(looksArabic('مرحبا بكم في العين'), isTrue);
    expect(looksArabic('Welcome to Al Ain'), isFalse);
  });
}
