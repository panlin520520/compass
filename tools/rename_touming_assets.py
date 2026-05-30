import os
from pathlib import Path


BASE = Path(r"E:\project\my\compassFlutter\flutter_application_1\assets")

MAPPINGS = [
    # touming-black
    ("touming-black", "综合盘黑线条.png", "comprehensive_plate_black_lines.png"),
    ("touming-black", "玄空盘黑线条.png", "xuan_kong_plate_black_lines.png"),
    ("touming-black", "三元盘黑线条.png", "sanyuan_plate_black_lines.png"),
    ("touming-black", "玄空飞星黑线条.png", "xuan_kong_flying_stars_black_lines.png"),
    ("touming-black", "向上十二长生黑线条.png", "upward_twelve_changsheng_black_lines.png"),
    ("touming-black", "三合盘黑线条.png", "sanhe_plate_black_lines.png"),
    ("touming-black", "入门盘黑线条.png", "beginner_plate_black_lines.png"),
    ("touming-black", "九星翻卦黑线条.png", "nine_stars_fan_gua_black_lines.png"),
    ("touming-black", "龙门八局黑线条.png", "longmen_baju_black_lines.png"),
    ("touming-black", "金锁玉关盘黑线条.png", "jinsuo_yuguan_plate_black_lines.png"),
    ("touming-black", "八卦黑线条.png", "bagua_black_lines.png"),
    ("touming-black", "八宅风水黑线条.png", "bazhai_fengshui_black_lines.png"),
    ("touming-black", "简易盘 黑线条.png", "simple_plate_black_lines.png"),
    # touming-white
    ("touming-white", "综合盘白线条.png", "comprehensive_plate_white_lines.png"),
    ("touming-white", "玄空盘白线条.png", "xuan_kong_plate_white_lines.png"),
    ("touming-white", "三元盘白线条.png", "sanyuan_plate_white_lines.png"),
    ("touming-white", "玄空飞星白线条.png", "xuan_kong_flying_stars_white_lines.png"),
    ("touming-white", "向上十二长生白线条.png", "upward_twelve_changsheng_white_lines.png"),
    ("touming-white", "三合盘白线条.png", "sanhe_plate_white_lines.png"),
    ("touming-white", "入门盘白线条.png", "beginner_plate_white_lines.png"),
    ("touming-white", "九星翻卦白线条.png", "nine_stars_fan_gua_white_lines.png"),
    ("touming-white", "龙门八局白线条.png", "longmen_baju_white_lines.png"),
    ("touming-white", "金锁玉关盘白线条.png", "jinsuo_yuguan_plate_white_lines.png"),
    ("touming-white", "八卦白线条.png", "bagua_white_lines.png"),
    ("touming-white", "八宅风水白线条.png", "bazhai_fengshui_white_lines.png"),
    ("touming-white", "简易盘 白线条.png", "simple_plate_white_lines.png"),
]


def main() -> None:
    if not BASE.exists():
        raise SystemExit(f"BASE not found: {BASE}")

    # Pre-flight checks
    for d, old, new in MAPPINGS:
        src = BASE / d / old
        dst = BASE / d / new
        if not src.exists():
            raise SystemExit(f"Missing source: {src}")
        if dst.exists():
            raise SystemExit(f"Destination already exists: {dst}")

    # Rename
    for d, old, new in MAPPINGS:
        src = BASE / d / old
        dst = BASE / d / new
        os.rename(src, dst)
        print(f"OK: {d}/{old} -> {new}")

    print("Done.")


if __name__ == "__main__":
    main()

