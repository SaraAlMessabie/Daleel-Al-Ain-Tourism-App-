"""Rebuilds the map's JSON copies from assets/db/al_ain.db, so the map and the rest of the app show the same data.

The database is the one source of truth. Run this after every change to places or bus data:
    python3 plugins/daleel/scripts/export_map_json.py
check_data.py fails if the JSON and the database disagree.
"""
import json
import sqlite3

DB = "assets/db/al_ain.db"
ATTRACTION_KEYS = [
    "attraction_id", "category_id", "name_en", "name_ar", "latitude", "longitude", "entry_price_aed",
    "opening_hours", "opening_hours_ar", "dress_code_note", "dress_code_note_ar", "image_path",
    "is_family_friendly", "is_active", "popularity_score", "avg_visit_duration_mins", "last_update",
]


def attractions(c):
    c.row_factory = sqlite3.Row
    rows = c.execute(
        "SELECT * FROM attractions WHERE is_active = 1 AND latitude IS NOT NULL AND longitude IS NOT NULL "
        "ORDER BY attraction_id"
    ).fetchall()
    return [{k: r[k] for k in ATTRACTION_KEYS if k in r.keys()} for r in rows]


def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    data = attractions(c)
    with open("assets/data/attractions.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # Arabic bus names and destinations (the map reads the bus JSON files).
    routes = json.load(open("assets/data/bus_routes.json", encoding="utf-8"))
    for r in routes:
        r["name_ar"] = f"حافلة المدينة {r['route_number']}"
    json.dump(routes, open("assets/data/bus_routes.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    stops = {s["stop_id"]: s for s in json.load(open("assets/data/bus_stops.json", encoding="utf-8"))}
    links = json.load(open("assets/data/route_stops.json", encoding="utf-8"))
    last = {}
    for l in links:
        if l["direction_id"] not in last or l["stop_sequence"] > last[l["direction_id"]]["stop_sequence"]:
            last[l["direction_id"]] = l
    directions = json.load(open("assets/data/route_directions.json", encoding="utf-8"))
    for d in directions:
        end = last.get(d["direction_id"])
        name_ar = stops.get(end["stop_id"], {}).get("name_ar") if end else None
        if name_ar:
            d["destination_ar"] = name_ar
            d["description_ar"] = name_ar
    json.dump(directions, open("assets/data/route_directions.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"Wrote {len(data)} attractions, {len(routes)} routes, {len(directions)} directions")


if __name__ == "__main__":
    main()
