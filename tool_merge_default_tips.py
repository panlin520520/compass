# -*- coding: utf-8 -*-
import json
import pathlib

base = pathlib.Path(__file__).resolve().parent / "assets" / "default-tip-json"
out_obj = {}
for p in sorted(base.glob("*.json")):
    if p.name == "index.json":
        continue
    key = p.stem
    with p.open("r", encoding="utf-8") as f:
        out_obj[key] = json.load(f)

merged = pathlib.Path(__file__).resolve().parent / "assets" / "default_tip_layers.json"
with merged.open("w", encoding="utf-8") as f:
    json.dump(out_obj, f, ensure_ascii=False, separators=(",", ":"))
print("merged", len(out_obj), "layers ->", merged, "size", merged.stat().st_size)
