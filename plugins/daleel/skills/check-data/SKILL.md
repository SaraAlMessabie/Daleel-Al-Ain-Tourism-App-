---
name: check-data
description: Validate the Daleel app's bundled data and strings (attractions, categories, images, RAG index, EN/AR key parity). Use after any data or strings change and before committing.
---

# Check Daleel data

Run from the repo root:

```
python3 plugins/daleel/scripts/check_data.py
```

It checks that attraction ids are unique, categories and image files exist, coordinates are plausible for Al Ain, RAG chunks point at real attractions, and `_en`/`_ar` in `lib/strings.dart` have the same keys and placeholders. Exit code 1 means problems were found; fix them and rerun. Report the output to the user.
