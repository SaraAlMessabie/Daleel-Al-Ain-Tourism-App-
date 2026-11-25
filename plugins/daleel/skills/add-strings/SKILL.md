---
name: add-strings
description: Add or change user-visible text in the Daleel app in both English and Arabic (lib/strings.dart). Use whenever a screen needs new or changed text.
---

# Add bilingual strings

All on-screen text is in `lib/strings.dart` as two const maps, `_en` and `_ar`.

Rules:
1. Every key must exist in BOTH maps. Add the English and the Arabic entry together.
2. Keys follow the existing prefixes by area (`a_` assistant, `it_` itinerary, `q_` onboarding, `cam_` camera, `tab_` tabs, `p_` profile). Reuse a prefix; do not create near-duplicate keys.
3. Placeholders use `{x}` and must appear identically in both languages.
4. Arabic should be natural Modern Standard Arabic, matching the tone of nearby entries. If unsure of a translation, say so rather than guessing silently.
5. Use the key from widgets via the existing lookup helper in `strings.dart`; never hard-code text in a widget.
6. Run `python3 plugins/daleel/scripts/check_data.py` afterwards; it reports keys missing from either map.
