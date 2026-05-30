# -*- coding: utf-8 -*-
"""Merge assets/default-tip-json/*.json (except index) -> assets/default_tip_layers.json"""
import json
import pathlib

base = pathlib.Path(__file__).resolve().parent / "assets" / "default-tip-json"
out_obj = {}
for p in sorted(base.glob("*.json")):
    if p.name == "index.json":
        continue
    with p.open("r", encoding="utf-8") as f:
        out_obj[p.stem] = json.load(f)

merged = pathlib.Path(__file__).resolve().parent / "assets" / "default_tip_layers.json"
with merged.open("w", encoding="utf-8") as f:
    json.dump(out_obj, f, ensure_ascii=False, separators=(",", ":"))
print("OK:", merged, "layers:", len(out_obj))
