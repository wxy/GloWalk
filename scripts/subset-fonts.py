#!/usr/bin/env python3
"""Subset the LXGW WenKai fonts to the characters GloWalk actually renders.

The full CJK fonts are ~25 MB each (103 MB total) and are *not* thinned by
App Store app thinning, so every user downloads all four. The app's rendered
text comes from a fixed set of sources (string catalog, taglines, lunar-date
tables, units), so each face can be subset to:

  * every character in Localizable.xcstrings + InfoPlist.xcstrings +
    Taglines.json (both keys and values — SwiftUI falls back to key-as-text)
  * hardcoded runtime strings (lunar month/day names, fallback taglines)
  * GB2312 Level-1 common characters (the 3755 most common Simplified
    Chinese characters), so future UI copy keeps the WenKai look
  * ASCII / Latin-1 plus the punctuation and symbols used by format strings

The original full fonts can be re-downloaded from:
    https://github.com/lxgw/LxgwWenKai/releases

Usage:
    python3 scripts/subset-fonts.py [FONT_DIR]

Default FONT_DIR is GloWalk/Resources/Fonts (relative to the repo root).
"""

import json
import sys
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FONT_DIR = REPO_ROOT / "GloWalk" / "Resources" / "Fonts"


def text_from_xcstrings(path: Path) -> str:
    """Return every string value *and* every key (keys render as text when a
    localization is missing) from an .xcstrings catalog."""
    data = json.loads(path.read_text(encoding="utf-8"))
    parts: list[str] = []
    for key, entry in data.get("strings", {}).items():
        parts.append(key)
        for lang, loc in entry.get("localizations", {}).items():
            unit = loc.get("stringUnit") or loc.get("variations", {}).get("plural", {}).get("other")
            if isinstance(unit, dict) and unit.get("value"):
                parts.append(str(unit["value"]))
    return "".join(parts)


def text_from_taglines(path: Path) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    parts: list[str] = []
    for item in data:
        for value in item.values():
            if isinstance(value, str):
                parts.append(value)
    return "".join(parts)


HARDCODED_STRINGS = [
    # LunarDate.swift — Chinese month/day tables (rendered at runtime)
    "正月二月三月四月五月六月七月八月九月十月冬月腊月",
    "初一初二初三初四初五初六初七初八初九初十十一十二十三十四十五十六十七十八十九二十廿一廿二廿三廿四廿五廿六廿七廿八廿九三十",
    # Tagline.swift fallback pool
    "踽踽独行，脚下有光踽踽獨行，腳下有光A solitary step, a lantern aglowGloWalk 随行路灯GloWalk 隨行路燈GloWalk — your night companion",
    # PosterGenerator date formats
    "M月d日M/d",
]


def gb2312_level1_chars() -> str:
    """The 3755 most common Simplified Chinese characters (GB2312 level 1,
    pinyin-sorted 区 16-55, encoded first byte 0xB0-0xD7)."""
    chars: list[str] = []
    for cp in range(0x3400, 0x9FFF + 1):
        ch = chr(cp)
        try:
            raw = ch.encode("gb2312")
        except UnicodeEncodeError:
            continue
        if len(raw) == 2 and 0xB0 <= raw[0] <= 0xD7:
            chars.append(ch)
    return "".join(chars)


BASE_RANGES = [
    (0x0020, 0x007E),   # ASCII
    (0x00A0, 0x00FF),   # Latin-1 supplement
    (0x3000, 0x303F),   # CJK punctuation
]

BASE_EXTRA = (
    "·×÷±≤≥∞→—…“”‘’《》〈〉【】「」『』、。，；：？！（）"
    "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
    "\u2013\u2014\u2018\u2019\u201A\u201B\u201C\u201D\u201E\u2026"
)


def used_text() -> str:
    parts = list(HARDCODED_STRINGS)
    for rel in [
        "GloWalk/Resources/Localizable.xcstrings",
        "GloWalk/Resources/InfoPlist.xcstrings",
        "GloWalk/Resources/Taglines.json",
    ]:
        path = REPO_ROOT / rel
        if path.suffix == ".json" and path.name == "Taglines.json":
            parts.append(text_from_taglines(path))
        else:
            parts.append(text_from_xcstrings(path))
    parts.append(gb2312_level1_chars())
    return "".join(parts)


def unicodes_from_text(text: str) -> set[int]:
    return {ord(ch) for ch in text if ord(ch) > 0x1F}


def subset_font(src: Path, dst: Path, unicodes: set[int]) -> None:
    opts = Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_glyph = True
    opts.notdef_outline = True
    opts.recommended_glyphs = True
    opts.glyph_names = True
    opts.legacy_cmap = True
    opts.symbol_cmap = True

    font = TTFont(src)
    source_cmap = set()
    for table in font["cmap"].tables:
        if table.isUnicode():
            source_cmap |= set(table.cmap.keys())
    subsetter = Subsetter(options=opts)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)
    font.save(dst)
    return source_cmap


def missing_chars(font_path: Path, source_cmap: set[int],
                  unicodes: set[int]) -> set[int]:
    font = TTFont(font_path)
    subset_cmap = set()
    for table in font["cmap"].tables:
        if table.isUnicode():
            subset_cmap |= set(table.cmap.keys())
    # A regression only if a *requested* character that existed in the source
    # font did not survive subsetting. Code points we requested from broad
    # ranges but that the font never had are fine.
    required = source_cmap & unicodes
    return required - subset_cmap


def main() -> None:
    font_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_FONT_DIR
    faces = [
        "LXGWWenKai-Light.ttf",
        "LXGWWenKai-Regular.ttf",
        "LXGWWenKai-Medium.ttf",
        "LXGWWenKaiMono-Light.ttf",
    ]
    unicodes = unicodes_from_text(used_text())
    for start, end in BASE_RANGES:
        unicodes |= set(range(start, end + 1))
    unicodes |= {ord(ch) for ch in BASE_EXTRA}
    unicodes.add(0xF8FF)  # Apple logo used by " Weather"

    total_before = 0
    total_after = 0
    for face in faces:
        src = font_dir / face
        if not src.exists():
            print(f"SKIP {face}: not found")
            continue
        size_before = src.stat().st_size
        tmp = src.with_suffix(".subset.ttf")
        source_cmap = subset_font(src, tmp, unicodes)
        # Sanity check: every used character must survive in the subset.
        missing = missing_chars(tmp, source_cmap, unicodes)
        if missing:
            sample = " ".join(f"U+{cp:04X}" for cp in sorted(missing)[:20])
            print(f"WARN {face}: {len(missing)} requested chars missing from subset: {sample}")
        else:
            covered = len(source_cmap & unicodes)
            print(f"OK   {face}: all {covered} requested glyphs preserved")
        tmp.replace(src)
        size_after = src.stat().st_size
        total_before += size_before
        total_after += size_after
        print(f"{face}: {size_before / 1e6:.1f}MB -> {size_after / 1e6:.1f}MB")
    print(f"TOTAL: {total_before / 1e6:.1f}MB -> {total_after / 1e6:.1f}MB "
          f"({(1 - total_after / total_before) * 100:.0f}% reduction)")


if __name__ == "__main__":
    main()
