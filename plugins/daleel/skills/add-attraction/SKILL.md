---
name: add-attraction
description: Add or edit an attraction in the Daleel app's bundled data (assets/db/al_ain.db, then the map's JSON copy), with its image and RAG entry. Use when asked to add a place, fix hours or prices, or change an attraction.
---

# Add or edit an attraction

The database `assets/db/al_ain.db` (table `attractions`) is the one source of truth. The map reads `assets/data/attractions.json`, which is generated from it by `python3 plugins/daleel/scripts/export_map_json.py`; never edit the JSON by hand. Main columns:
`attraction_id`, `category_id`, `name_en`, `name_ar`, `entry_price_aed`, `dress_code_note` + `dress_code_note_ar`, `opening_hours` + `opening_hours_ar`, `best_time_to_visit` + `_ar`, `closed_days` + `_ar`, `longitude`, `latitude`, `image_path`, `avg_rating`, `rating_count`, `popularity_score`, `avg_visit_duration_mins`, `is_family_friendly` (0/1), `is_active` (0/1), `last_update` (`YYYY-MM-DD HH:MM:SS`).

Steps:
1. Ask for any missing facts (English and Arabic name, category, price, hours, coordinates). Never invent hours, prices or coordinates; mark them unknown and say so.
2. `category_id` must exist in `assets/data/categories.json`.
3. New `attraction_id` = current max + 1. Never reuse or renumber ids: itineraries and `rag_index.json` refer to them.
4. `image_path` is relative to `assets/`, e.g. `images/al_ain_oasis.jpg`. The file must exist in `assets/images/` (snake_case name of the place).
5. Set `last_update` to now. Fill every `_ar` column. Then run `export_map_json.py` to refresh the map's JSON.
6. `assets/data/rag_index.json` holds one chunk per attraction (`type: "attraction"`, `source_id` = attraction_id) with an embedding `vec`. Claude cannot compute these embeddings. Tell the user the index must be rebuilt with their embedding pipeline (model `embeddinggemma-2-text-270m`) and do not hand-edit `vec`.
7. Any change to the database must be accompanied by raising `Db.bundledDbVersion` in `lib/data.dart`, otherwise existing installs never receive the new data.
8. Run the `check-data` skill before finishing.
