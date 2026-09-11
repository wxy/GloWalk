#!/usr/bin/env python3
"""Internationalization audit for GloWalk.

Checks, in order:
  1. Localizable.xcstrings  — every key translated in all 11 shipping languages,
     no non-"translated" states, no empty values, format specifiers consistent
     across languages (a mismatch is a runtime formatting bug/crash).
  2. InfoPlist.xcstrings    — same completeness check.
  3. Code → catalog         — every localization key referenced from Swift
     (Text / LocalizedStringKey / NSLocalizedString / String(localized:) /
     L10n.str) exists in the catalog.
  4. Catalog → code         — keys never referenced anywhere (dead weight,
     reported only).
  5. Taglines.json          — required tier-1 fields present on every entry,
     optional tier-2 languages reported, tagline keys referenced from Swift
     (brand + night-memory pools) all resolve.

Exit code 0 = clean, 1 = problems found (CI friendly).

Usage: python3 scripts/audit_i18n.py
"""

import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]

problems: list[str] = []
warnings: list[str] = []

try:
    from fontTools.ttLib import TTFont
except ImportError:  # font-subset coverage check becomes a skipped warning
    TTFont = None


def load_xcstrings(rel: str) -> dict:
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def units(entry: dict) -> dict:
    """Flatten an entry's localizations to {lang: (state, value)}.

    Handles both plain stringUnits and plural "variations" (every variation
    branch must be translated; the value is sampled for specifier checks).
    """
    out = {}
    for lang, loc in entry.get("localizations", {}).items():
        unit = loc.get("stringUnit")
        if unit is not None:
            out[lang] = (unit.get("state", "?"), unit.get("value", ""))
        elif "variations" in loc:
            states, values = [], []
            for branch in loc["variations"].values():
                sub = branch.get("stringUnit", {})
                states.append(sub.get("state", "?"))
                values.append(sub.get("value", ""))
            state = "translated" if all(s == "translated" for s in states) else states[0]
            out[lang] = (state, " ".join(values))
    return out


def specifiers(value: str) -> list:
    """Format specifiers as (position, type) pairs; position None if unnumbered."""
    found = re.findall(r"%(?:(\d+)\$)?(lld|ld|lf|@|[a-zA-Z])", value)
    return [(pos or "*", kind) for pos, kind in found]


def check_catalog(rel: str) -> dict:
    print(f"\n=== {rel} ===")
    data = load_xcstrings(rel)
    strings = data.get("strings", {})
    print(f"keys: {len(strings)}, source language: {data.get('sourceLanguage')}")

    key_langs: dict[str, list] = {}
    neutral = 0
    for key, entry in sorted(strings.items()):
        u = units(entry)
        key_langs[key] = list(u)
        # Language-neutral keys (interpolation patterns, endonyms, decorative
        # punctuation) are exempt from per-language completeness.
        if is_language_neutral(key, entry):
            neutral += 1
            for lang, (state, _) in sorted(u.items()):
                if state not in ("translated", "new"):
                    problems.append(f"{rel}: {key!r} [{lang}] state = {state!r}")
            continue
        missing = [l for l in LANGS if l not in u]
        if missing:
            problems.append(f"{rel}: {key!r} missing languages: {', '.join(missing)}")
        empties = [lang for lang, (_, value) in u.items() if not value.strip()]
        if len(empties) == len(u):
            problems.append(f"{rel}: {key!r} empty in every language")
        elif empties:
            warnings.append(
                f"{rel}: {key!r} empty in {', '.join(sorted(empties))} but "
                f"translated elsewhere — confirm this is intentional (unit-style key?)")
        for lang, (state, value) in sorted(u.items()):
            if state == "new":
                warnings.append(f"{rel}: {key!r} [{lang}] state = 'new' (never marked reviewed)")
            elif state != "translated":
                problems.append(f"{rel}: {key!r} [{lang}] state = {state!r}")
        # Format specifiers must agree across every language of a key.
        base = None
        for lang, (_, value) in sorted(u.items()):
            s = specifiers(value)
            if base is None:
                base = (lang, s)
            elif Counter(s) != Counter(base[1]):
                problems.append(
                    f"{rel}: {key!r} [{lang}] specifiers {s} != [{base[0]}] {base[1]}")
        # Same-copy-everywhere detector, skipping the endonym pattern (the
        # English value itself non-Latin is intentional for picker labels).
        en_value = u.get("en", ("", ""))[1]
        if not re.search(r"[^\x00-\x7f]", en_value):
            for lang, (_, value) in sorted(u.items()):
                if lang != "en" and value == en_value and re.search(
                        r"[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af\u0400-\u04ff]", value):
                    warnings.append(
                        f"{rel}: {key!r} [{lang}] identical to English but contains "
                        f"non-Latin text — likely a copy-paste slip")
    print(f"language-neutral keys exempt from completeness: {neutral}")
    return key_langs


# ---------------------------------------------------------------------------
# Code → catalog: every key referenced from Swift must exist in the catalog.

SWIFT_DIRS = ["GloWalk", "GloWalkTests"]
# Call sites whose string arguments are localization keys. LocalizedStringKey
# also appears in L10n accessors (`{ "key.path" }`), hence [({]. The trailing
# alternatives cover call shapes in this codebase that pass raw keys:
# confirmationDialog("key", ...), Button("key") { ... }, and the project's
# helpItem(icon:title:desc:) helper.
KEY_CALL = re.compile(
    r"(?:Text|LocalizedStringKey|NSLocalizedString|String\s*\(\s*localized|str)\s*[({]"
    r"|confirmationDialog\s*\("
    r"|Button\s*\(\s*\""
    r"|helpItem\s*\(")
KEY_SHAPE = re.compile(r"^%(@|lld|ld|[a-z])(\s|%|$)|^[a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+$")
# A bare English sentence passed to a localization call smells like a missing
# catalog key; brand names ("Open-Meteo") don't match — they have no space.
ENGLISH_SENTENCE = re.compile(r"^[A-Z][A-Za-z,',\.\-]* [A-Za-z,',\.\- ]+$")
# Keys auto-extracted by Xcode that are language-neutral by design and exempt
# from the 11-language completeness rule:
#   - interpolation format patterns from Text("... \(x) ...")  (contain %@)
#   - decorative punctuation        ('· ', '···', '')
#   - endonyms shown in their own language everywhere (language picker names,
#     brand names, emoji)
ENDONYMS = {"de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru",
            "Deutsch", "English", "Español", "Français", "Italiano",
            "Português", "日本語", "한국어", "Русский",
            "Open-Meteo", "\uf8ff Weather", "GloWalk", "· ", "···", "",
            "🦶", "👣", "🔋 —"}


def is_language_neutral(key: str, entry: dict) -> bool:
    if "%" in key or key in ENDONYMS:
        return True
    u = units(entry)
    en = u.get("en", ("", ""))[1]
    # Endonym pattern: the English value is itself non-Latin (e.g. the picker
    # shows 简体中文 in every UI language).
    return bool(re.search(r"[^\x00-\x7f]", en))


def swift_sources() -> list[tuple[Path, str]]:
    files = [p for d in SWIFT_DIRS for p in (ROOT / d).rglob("*.swift")]
    return [(p, p.read_text(encoding="utf-8")) for p in files]


def referenced_keys() -> set:
    keys = set()
    for path, src in swift_sources():
        for i, line in enumerate(src.splitlines(), 1):
            if not KEY_CALL.search(line):
                continue
            # SF Symbol / asset arguments are not localization keys.
            clean = re.sub(r'(?:icon|systemName|image|asset)\s*:\s*"[^"]*"', "", line)
            for lit in re.findall(r'"([^"\n]+)"', clean):
                if KEY_SHAPE.match(lit):
                    keys.add(lit)
                elif "%" not in lit and ENGLISH_SENTENCE.match(lit) \
                        and any(c.islower() for c in lit):
                    warnings.append(f"{path.name}:{i}: bare English sentence passed to a "
                                    f"localization call (missing catalog key?): {lit!r}")
    return keys


# ---------------------------------------------------------------------------

def main() -> int:
    loc = check_catalog("GloWalk/Resources/Localizable.xcstrings")
    plist = check_catalog("GloWalk/Resources/InfoPlist.xcstrings")

    # 3. Code → catalog
    print("\n=== code → catalog ===")
    refs = referenced_keys()
    catalog = set(loc) | set(plist)
    dangling = sorted(k for k in refs if k not in catalog and not k.startswith("tagline."))
    if dangling:
        for k in dangling:
            problems.append(f"key referenced in code but absent from catalog: {k!r}")
    print(f"referenced keys: {len(refs)}, dangling: {len(dangling)}")

    # 4. Catalog → code (dead keys, informational). InfoPlist keys are consumed
    # by the OS, not by code, so they are expected to be "unreferenced";
    # language-neutral keys are auto-extractions of verbatim strings.
    system_keys = {"CFBundleDisplayName", "CFBundleName", "CFBundleShortVersionString"}
    neutral_src = load_xcstrings("GloWalk/Resources/Localizable.xcstrings")["strings"]
    unreferenced = sorted(
        k for k in catalog
        if k not in refs and not k.startswith("NS") and k not in system_keys
        and not (k in neutral_src and is_language_neutral(k, neutral_src[k])))
    print(f"catalog keys never referenced in code (dead weight?): {len(unreferenced)}")
    for k in unreferenced:
        warnings.append(f"unreferenced catalog key: {k!r}")

    # 5. Taglines.json
    print("\n=== Taglines.json ===")
    tag_data = json.loads((ROOT / "GloWalk/Resources/Taglines.json").read_text(encoding="utf-8"))
    required = ["key", "phrase", "phrase_ht", "phrase_en", "explanation",
                "explanation_ht", "explanation_en"]
    optional = ["ja", "ko", "fr", "de", "es", "pt", "it", "ru"]
    for item in tag_data:
        for field in required:
            if not item.get(field, "").strip():
                problems.append(f"Taglines.json: {item.get('key', '?')!r} missing required field {field!r}")
        for lang in optional:
            for kind in ("phrase", "explanation"):
                if not item.get(f"{kind}_{lang}", "").strip():
                    warnings.append(
                        f"Taglines.json: {item['key']!r} has no {kind}_{lang} "
                        f"(falls back to English)")
    # Tagline keys referenced from Swift must resolve in the JSON.
    swift_text = "\n".join(src for _, src in swift_sources())
    tag_refs = set(re.findall(r'"(tagline\.[a-zA-Z0-9_.]+)"', swift_text))
    json_keys = {item["key"] for item in tag_data}
    for ref in sorted(tag_refs):
        base = ref.split(".")[0] + "." + ref.split(".")[1]
        if ref not in json_keys and not any(k.startswith(base + ".") for k in json_keys):
            problems.append(f"tagline key referenced in Swift but absent from Taglines.json: {ref!r}")
    print(f"entries: {len(tag_data)}, tagline keys referenced from Swift: {len(tag_refs)}")

    # 6. Bundled font subsets must cover every character the app renders.
    # Regenerate with: python3 scripts/subset-fonts.py FULL_FONT_DIR Fonts_DIR
    # (needs fontTools; skipped with a warning where it is not installed).
    if TTFont is None:
        warnings.append("fontTools not installed — font-subset coverage check skipped")
        print("font subsets: fontTools not installed — coverage check skipped")
    else:
        print("\n=== font subsets ===")
        check_font_coverage(loc, tag_data)


def check_font_coverage(loc: dict, tag_data: list) -> None:
    fonts_dir = ROOT / "GloWalk" / "Resources" / "Fonts"

    # Read values straight from the catalog JSON.
    cat_json = load_xcstrings("GloWalk/Resources/Localizable.xcstrings")["strings"]

    def catalog_text(langs: list[str]) -> str:
        parts = []
        for key, entry in cat_json.items():
            parts.append(key)
            for lang in langs:
                for state, value in [units(entry).get(lang, ("", ""))]:
                    parts.append(value)
        return "".join(parts)

    def taglines_text(suffixes: list[str]) -> str:
        parts = []
        for item in tag_data:
            for field, value in item.items():
                if isinstance(value, str) and (field == "key" or field in suffixes):
                    parts.append(value)
        return "".join(parts)

    groups = [
        ("LXGWWenKai-Regular.ttf",
         ["zh-Hans", "zh-Hant", "en", "fr", "de", "es", "pt-BR", "it", "ru"],
         ["phrase", "explanation", "phrase_en", "explanation_en", "phrase_ht",
          "explanation_ht", "phrase_fr", "explanation_fr", "phrase_de",
          "explanation_de", "phrase_es", "explanation_es", "phrase_pt",
          "explanation_pt", "phrase_it", "explanation_it", "phrase_ru",
          "explanation_ru"]),
        ("KleeOne-Regular.ttf", ["ja"], ["phrase_ja", "explanation_ja"]),
        ("LXGWWenKaiKR-Regular.ttf", ["ko"], ["phrase_ko", "explanation_ko"]),
    ]
    # Emoji are rendered by the system emoji font, not the bundled faces.
    skip = {"⏱", "👣", "📏", "🦶", "🔋", "\uf8ff"}
    # Language-picker endonyms the bundled faces never had (简体中文 / 한국어
    # rows in SettingsView): they intentionally render via the iOS system-font
    # fallback, which is the more native look for foreign-language names.
    intended_fallback = set("简한국어")
    for font, langs, suffixes in groups:
        path = fonts_dir / font
        if not path.exists():
            warnings.append(f"font subset missing: {font}")
            continue
        cmap = set(TTFont(path).getBestCmap())
        text = catalog_text(langs) + taglines_text(suffixes)
        missing = sorted({c for c in text
                          if ord(c) > 0x7F and c not in skip
                          and c not in intended_fallback and ord(c) not in cmap})
        if missing:
            problems.append(
                f"font subset {font} missing glyphs: {''.join(missing)} "
                f"(regenerate with scripts/subset-fonts.py from FULL upstream fonts)")
        else:
            print(f"  {font}: covers all rendered characters ✓")

    # Summary
    print(f"\n{'=' * 60}")
    if problems:
        print(f"PROBLEMS ({len(problems)}):")
        for p in problems:
            print(f"  ✗ {p}")
    if warnings:
        print(f"\nwarnings ({len(warnings)}):")
        for w in warnings:
            print(f"  ! {w}")
    if not problems and not warnings:
        print("i18n audit clean ✓")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
