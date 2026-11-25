#!/usr/bin/env python3
"""Validate Daleel bundled data. Run from the repo root."""
import json, os, re, sys

errors = []
def err(m): errors.append(m)

att = json.load(open("assets/data/attractions.json", encoding="utf-8"))
cats = {c["category_id"] for c in json.load(open("assets/data/categories.json", encoding="utf-8"))}
ids = [a["attraction_id"] for a in att]
if len(ids) != len(set(ids)): err("duplicate attraction_id values")
for a in att:
    n = a.get("name_en", a["attraction_id"])
    if a["category_id"] not in cats: err(f"{n}: unknown category_id {a['category_id']}")
    if not a.get("name_ar"): err(f"{n}: missing name_ar")
    if not os.path.exists(os.path.join("assets", a["image_path"])): err(f"{n}: image missing {a['image_path']}")
    if not (24.0 <= a["latitude"] <= 24.5 and 55.4 <= a["longitude"] <= 56.0): print(f"WARN: {n}: coordinates ({a['latitude']}, {a['longitude']}) look outside the Al Ain area")
    if a["entry_price_aed"] < 0: err(f"{n}: negative price")

rag = json.load(open("assets/data/rag_index.json", encoding="utf-8"))
idset = set(ids)
for c in rag["chunks"]:
    if c["type"] == "attraction" and c["source_id"] not in idset: err(f"rag chunk {c['id']}: unknown attraction {c['source_id']}")
have = {c["source_id"] for c in rag["chunks"] if c["type"] == "attraction"}
for a in att:
    if a["is_active"] and a["attraction_id"] not in have: err(f"{a['name_en']}: no RAG chunk (index needs rebuilding)")

src = open("lib/strings.dart", encoding="utf-8").read()
def block(name):
    m = re.search(r"const Map<String, String> %s = \{(.*?)\n\};" % name, src, re.S)
    return dict(re.findall(r"'([^']+)':\s*'((?:[^'\\]|\\.)*)'", m.group(1)))
en, ar = block("_en"), block("_ar")
for k in sorted(set(en) ^ set(ar)): err(f"strings: key '{k}' only in {'_en' if k in en else '_ar'}")
for k in set(en) & set(ar):
    if sorted(re.findall(r"\{\w+\}", en[k])) != sorted(re.findall(r"\{\w+\}", ar[k])): err(f"strings: placeholder mismatch in '{k}'")

print(f"{len(att)} attractions, {len(rag['chunks'])} rag chunks, {len(en)} en / {len(ar)} ar strings")
for e in errors: print("ERROR:", e)
print("OK" if not errors else f"{len(errors)} problem(s)")
sys.exit(1 if errors else 0)
