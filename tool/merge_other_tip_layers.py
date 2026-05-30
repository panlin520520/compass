"""Merge assets/other-tip-json/*.json into assets/other_tip_layers.json (UTF-8).

Run from flutter_application_1: python tool/merge_other_tip_layers.py
"""
from __future__ import annotations

import json
import os


def _decode_json_bytes(raw: bytes):
    for enc in ("utf-8-sig", "utf-8", "gbk"):
        try:
            return json.loads(raw.decode(enc))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    raise ValueError("cannot decode json")


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tip_dir = os.path.join(root, "assets", "other-tip-json")
    out_path = os.path.join(root, "assets", "other_tip_layers.json")

    merged: dict[str, object] = {}
    for name in sorted(os.listdir(tip_dir)):
        if not name.lower().endswith(".json"):
            continue
        if name == "index.json":
            continue
        path = os.path.join(tip_dir, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            raw = f.read()
        key = name[:-5] if name.endswith(".json") else name
        merged[key] = _decode_json_bytes(raw)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, separators=(",", ":"))

    print(f"wrote {len(merged)} layers -> {out_path}")


if __name__ == "__main__":
    main()
