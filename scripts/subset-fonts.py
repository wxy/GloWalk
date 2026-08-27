#!/usr/bin/env python3
"""Subset the bundled fonts to the characters GloWalk actually renders.

The full CJK fonts are large (WenKai ~25 MB/face, Klee One ~9 MB/face,
WenKai KR ~14 MB/face) and are *not* thinned by App Store app thinning, so
every user downloads every face. The app's rendered text comes from fixed
sources (string catalog, taglines, lunar-date tables, units), so each face can
be subset to:

  * the characters used by its language group's strings (Localizable.xcstrings
    + InfoPlist.xcstrings + Taglines.json — keys too, since SwiftUI falls back
    to key-as-text when a localization is missing)
  * hardcoded runtime strings (lunar month/day names, fallback taglines)
  * a "future buffer" of common characters per script, so future UI copy keeps
    the bundled look:
      - GB2312 Level-1 (3755 common Simplified Chinese characters) for WenKai
      - JIS X 0208 Level-1 (2965 common Japanese kanji) for Klee One
      - KS X 1001 (2350 common Hangul syllables) for WenKai KR
  * ASCII / Latin-1 plus the punctuation and symbols used by format strings
  * Latin Extended-A/B + Vietnamese extensions + Cyrillic for the European
    languages (fr/de/es/pt-BR/it/ru) on the WenKai faces

Original full fonts:
  WenKai:     https://github.com/lxgw/LxgwWenKai/releases
  Klee One:   https://github.com/google/fonts (ofl/kleeone) / fontworks-fonts/Klee
  WenKai KR:  https://github.com/lxgw/LxgwWenkaiKR/releases

Usage:
    python3 scripts/subset-fonts.py [SRC_DIR] [OUT_DIR]

Default SRC_DIR/OUT_DIR is GloWalk/Resources/Fonts (relative to the repo root).
"""

import json
import sys
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FONT_DIR = REPO_ROOT / "GloWalk" / "Resources" / "Fonts"

# Language groups and which Taglines.json field suffix each maps to.
WENKAI_LANGS = ["en", "zh-Hans", "zh-Hant", "fr", "de", "es", "pt-BR", "it", "ru"]
JA_LANGS = ["ja"]
KO_LANGS = ["ko"]

TAGLINE_SUFFIX = {
    "en": "_en",
    "zh-Hans": "",
    "zh-Hant": "_ht",
    "ja": "_ja",
    "ko": "_ko",
    "fr": "_fr",
    "de": "_de",
    "es": "_es",
    "pt-BR": "_pt",
    "it": "_it",
    "ru": "_ru",
}


def text_from_xcstrings(path: Path, languages: list[str]) -> str:
    """Return every string key *and* the values for the given languages (keys
    render as text when a localization is missing)."""
    data = json.loads(path.read_text(encoding="utf-8"))
    parts: list[str] = []
    for key, entry in data.get("strings", {}).items():
        parts.append(key)
        for lang in languages:
            loc = entry.get("localizations", {}).get(lang)
            if not loc:
                continue
            unit = loc.get("stringUnit") or loc.get("variations", {}).get("plural", {}).get("other")
            if isinstance(unit, dict) and unit.get("value"):
                parts.append(str(unit["value"]))
    return "".join(parts)


def text_from_taglines(path: Path, languages: list[str]) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    parts: list[str] = []
    for item in data:
        for lang in languages:
            for field in ("phrase", "explanation"):
                value = item.get(field + TAGLINE_SUFFIX[lang])
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

# Japanese HUD units rendered in the WenKai Mono face (shinjitai 歩 is not in
# GB2312, so it must be requested explicitly for the mono face).
JA_MONO_UNITS = "歩分"

# Runtime lunar-date strings (LunarDate.swift) rendered per language. These are
# already covered by the JIS X 0208 level-1 / KS X 1001 buffers, but listed
# explicitly so a future buffer reduction can't silently drop them.
JA_LUNAR_STRINGS = (
    "旧暦睦月如月弥生卯月皐月水無月文月葉月長月神無月霜月師走"
    "一日二日三日四日五日六日七日八日九日十日"
    "十一日十二日十三日十四日十五日十六日十七日十八日十九日二十日"
    "二十一日二十二日二十三日二十四日二十五日二十六日二十七日二十八日二十九日三十日"
)
KO_LUNAR_STRINGS = "음력월일"


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


def jis_level1_chars() -> str:
    """The 2965 most common Japanese kanji (JIS X 0208 level 1, rows 16-47,
    which encode in EUC-JP with a first byte of 0xB0-0xCF)."""
    chars: list[str] = []
    for cp in range(0x4E00, 0x9FFF + 1):
        ch = chr(cp)
        try:
            raw = ch.encode("euc_jp")
        except UnicodeEncodeError:
            continue
        if len(raw) == 2 and 0xB0 <= raw[0] <= 0xCF:
            chars.append(ch)
    return "".join(chars)


def ko_common_syllables() -> str:
    """The 2350 Hangul syllables of KS X 1001 (the standard's "ga-na-da" table,
    ordered by frequency; the de-facto common-Korean set every Korean font
    ships). Stored as a separate data file so the script stays readable."""
    path = Path(__file__).resolve().parent / "ks-x-1001-syllables.txt"
    return path.read_text(encoding="utf-8").strip()


BASE_RANGES = [
    (0x0020, 0x007E),   # ASCII
    (0x00A0, 0x00FF),   # Latin-1 supplement
    (0x3000, 0x303F),   # CJK punctuation
]

# Latin Extended-A/B, Latin Extended Additional (Vietnamese), Cyrillic —
# the glyphs needed by the Tier-2 European languages (fr/de/es/pt-BR/it/ru).
# Verified against the full LXGW WenKai v1.522 fonts: Ext-A 128/128,
# Ext-B 208/208, VN 256/256, common Cyrillic letters (ru/uk/be/bg/sr) present.
EUROPEAN_RANGES = [
    (0x0100, 0x017F),   # Latin Extended-A
    (0x0180, 0x024F),   # Latin Extended-B
    (0x1E00, 0x1EFF),   # Latin Extended Additional (Vietnamese)
    (0x0400, 0x04FF),   # Cyrillic
]

# Japanese kana for the Klee One faces.
JP_RANGES = [
    (0x3040, 0x309F),   # Hiragana
    (0x30A0, 0x30FF),   # Katakana
]

BASE_EXTRA = (
    "·×÷±≤≥∞→—…“”‘’《》〈〉【】「」『』、。，；：？！（）"
    "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
    "\u2013\u2014\u2018\u2019\u201A\u201B\u201C\u201D\u201E\u2026"
)


def used_text_for(languages: list[str], extra: list[str]) -> str:
    parts = list(extra)
    for rel in [
        "GloWalk/Resources/Localizable.xcstrings",
        "GloWalk/Resources/InfoPlist.xcstrings",
        "GloWalk/Resources/Taglines.json",
    ]:
        path = REPO_ROOT / rel
        if path.suffix == ".json" and path.name == "Taglines.json":
            parts.append(text_from_taglines(path, languages))
        else:
            parts.append(text_from_xcstrings(path, languages))
    return "".join(parts)


def unicodes_from_text(text: str) -> set[int]:
    return {ord(ch) for ch in text if ord(ch) > 0x1F}


def rename_family(font: TTFont, family: str, typographic_family: str,
                  subfamily: str) -> None:
    """Rename a face so UIFont(name:) resolves via its English family name,
    mirroring the LXGW WenKai naming convention (e.g. "LXGW WenKai KR Medium").
    Only touches the name records that iOS consults."""
    for record in font["name"].names:
        if record.nameID in (1, 4):
            record.string = family
        elif record.nameID == 16:
            record.string = typographic_family
        elif record.nameID == 17:
            record.string = subfamily


def subset_font(src: Path, dst: Path, unicodes: set[int],
                rename: tuple[str, str, str] | None) -> set[int]:
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
    if rename:
        rename_family(font, *rename)
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


# (source, output, family rename, language groups, future set, extra text,
#  extra ranges)
FACES = [
    # ---- LXGW WenKai SC: zh / en / Tier-2 European languages ----
    ("LXGWWenKai-Light.ttf", "LXGWWenKai-Light.ttf", None,
     WENKAI_LANGS, gb2312_level1_chars(), HARDCODED_STRINGS, EUROPEAN_RANGES),
    ("LXGWWenKai-Regular.ttf", "LXGWWenKai-Regular.ttf", None,
     WENKAI_LANGS, gb2312_level1_chars(), HARDCODED_STRINGS, EUROPEAN_RANGES),
    ("LXGWWenKai-Medium.ttf", "LXGWWenKai-Medium.ttf", None,
     WENKAI_LANGS, gb2312_level1_chars(), HARDCODED_STRINGS, EUROPEAN_RANGES),
    # Mono also renders Japanese HUD units (歩/分) for the HUD data strip.
    ("LXGWWenKaiMono-Light.ttf", "LXGWWenKaiMono-Light.ttf", None,
     WENKAI_LANGS, gb2312_level1_chars(),
     HARDCODED_STRINGS + [JA_MONO_UNITS], EUROPEAN_RANGES),
    # ---- Klee One: Japanese (the original font LXGW WenKai derives from) ----
    ("KleeOne-Regular.ttf", "KleeOne-Regular.ttf", None,
     JA_LANGS, jis_level1_chars(), [JA_LUNAR_STRINGS], JP_RANGES),
    ("KleeOne-SemiBold.ttf", "KleeOne-SemiBold.ttf", None,
     JA_LANGS, jis_level1_chars(), [JA_LUNAR_STRINGS], JP_RANGES),
    # ---- LXGW WenKai KR: Korean (official Korean edition of WenKai) ----
    ("LXGWWenKaiKR-Light.ttf", "LXGWWenKaiKR-Light.ttf",
     ("LXGW WenKai KR Light", "LXGW WenKai KR", "Light"),
     KO_LANGS, ko_common_syllables(), [KO_LUNAR_STRINGS], []),
    ("LXGWWenKaiKR-Regular.ttf", "LXGWWenKaiKR-Regular.ttf",
     ("LXGW WenKai KR", "LXGW WenKai KR", "Regular"),
     KO_LANGS, ko_common_syllables(), [KO_LUNAR_STRINGS], []),
    ("LXGWWenKaiKR-Medium.ttf", "LXGWWenKaiKR-Medium.ttf",
     ("LXGW WenKai KR Medium", "LXGW WenKai KR", "Medium"),
     KO_LANGS, ko_common_syllables(), [KO_LUNAR_STRINGS], []),
    ("LXGWWenKaiMonoKR-Light.ttf", "LXGWWenKaiMonoKR-Light.ttf",
     ("LXGW WenKai Mono KR Light", "LXGW WenKai Mono KR", "Light"),
     KO_LANGS, ko_common_syllables(), [KO_LUNAR_STRINGS], []),
]


def main() -> None:
    args = [Path(a) for a in sys.argv[1:3]]
    src_dir = args[0] if args else DEFAULT_FONT_DIR
    out_dir = args[1] if len(args) > 1 else src_dir

    total_before = 0
    total_after = 0
    for face, out_name, rename, languages, future, extra, extra_ranges in FACES:
        src = src_dir / face
        if not src.exists():
            print(f"SKIP {face}: not found")
            continue
        dst = out_dir / out_name
        size_before = src.stat().st_size
        unicodes = unicodes_from_text(used_text_for(languages, extra))
        unicodes |= {ord(ch) for ch in future}
        for start, end in BASE_RANGES:
            unicodes |= set(range(start, end + 1))
        unicodes |= {ord(ch) for ch in BASE_EXTRA}
        for start, end in extra_ranges:
            unicodes |= set(range(start, end + 1))
        unicodes.add(0xF8FF)  # Apple logo used by " Weather"

        tmp = src.with_name(face + ".subset.ttf")
        source_cmap = subset_font(src, tmp, unicodes, rename)
        missing = missing_chars(tmp, source_cmap, unicodes)
        if missing:
            sample = " ".join(f"U+{cp:04X}" for cp in sorted(missing)[:20])
            print(f"WARN {face}: {len(missing)} requested chars missing from subset: {sample}")
        else:
            covered = len(source_cmap & unicodes)
            print(f"OK   {face}: all {covered} requested glyphs preserved")
        tmp.replace(dst)
        size_after = dst.stat().st_size
        total_before += size_before
        total_after += size_after
        print(f"{out_name}: {size_before / 1e6:.1f}MB -> {size_after / 1e6:.1f}MB")
    print(f"TOTAL: {total_before / 1e6:.1f}MB -> {total_after / 1e6:.1f}MB "
          f"({(1 - total_after / total_before) * 100:.0f}% reduction)")


if __name__ == "__main__":
    main()
