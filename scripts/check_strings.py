"""Checks that every L("…") key in the iOS sources exists in Localizable.xcstrings
with German and English values.

Interpolations are converted the way Swift's String.LocalizationValue does:
Int → %lld, everything else → %@. The type is decided by a small hint table,
since this script does not type-check Swift.

Usage: python -I scripts/check_strings.py [--list]
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "MeldePlanner"
SOURCE_DIRS = [SOURCES, ROOT / "Shared", ROOT / "MeldeWidgets", ROOT / "Packages"]
CATALOG = ROOT / "core/l10n/Localizable.xcstrings"
LANGUAGES = ("de", "en")

# Interpolated expressions that are integers (→ %lld); all others are strings (→ %@).
INT_EXPRESSIONS = {
    "goal", "remaining", "streak", "suggestion", "-weekOffset",
    "todayCount(for: current.subjectId)", "exam.pageCount",
    "entry.weekTotal", "entry.lessonCount", "entry.homeworkDue", "context.state.count",
    "context.state.weekTotal", "unassigned.count",
    "s.lessons", "s.changes", "code", "week", "minutes", "homework", "open", "more", "days", "added", "entry.streak", "lessonCount", "count", "entry.total", "late",
}

# Keys used outside L(…): widget gallery and App Intents metadata.
EXTRA_KEYS = {
    "Melden",
    "Laufende Stunde, Meldungen dieser Woche und Melden mit einem Tipp.",
    "Erfasst eine Meldung für die laufende Stunde.",
    "Meldo Statistik", "Deine Meldungen diese Woche.", "Stundenplan heute",
    "Deine Stunden heute, Ausfälle durchgestrichen.", "Was bald fällig ist.",
    # Android only.
    "Mit der Kamera, Seite für Seite",
    "Holt die Aufgaben aus deinen Teams-Klassen in deine Aufgabenliste.",
    # Android only: titles of Start cards this build doesn't show (DashboardScreen.kt, MoreScreen.kt).
    "Nachrichten", "Nächste Ferien",
}

CALL = re.compile(r'\b(?:L|LGerman|localize)\("((?:[^"\\]|\\.)*)"\)')
INTERP = re.compile(r"\\\((.*?)\)(?=[^)]*(?:\\\(|$))")


def to_key(raw: str) -> str:
    out, i = [], 0
    while i < len(raw):
        if raw.startswith("\\(", i):
            depth, j = 1, i + 2
            while depth:
                depth += {"(": 1, ")": -1}.get(raw[j], 0)
                j += 1
            expr = raw[i + 2 : j - 1]
            out.append("%lld" if expr in INT_EXPRESSIONS else "%@")
            i = j
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def source_keys() -> dict[str, set[str]]:
    keys: dict[str, set[str]] = {}
    for path in (p for d in SOURCE_DIRS for p in d.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in CALL.finditer(text):
            keys.setdefault(to_key(match.group(1)), set()).add(path.name)
    return keys


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # German/Turkish text on any console
    keys = source_keys()
    if "--list" in sys.argv:
        for key in sorted(keys):
            print(key)
        return 0
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    problems = []
    for key, files in sorted(keys.items()):
        entry = strings.get(key)
        if entry is None:
            problems.append(f"missing key: {key!r} ({', '.join(sorted(files))})")
            continue
        for lang in LANGUAGES:
            if lang == catalog["sourceLanguage"]:
                continue
            unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit")
            if not unit or not unit.get("value"):
                problems.append(f"no {lang} translation: {key!r}")
            elif unit["value"].count("%") != key.count("%"):
                problems.append(f"placeholder mismatch in {lang}: {key!r}")
    unused = sorted(set(strings) - set(keys) - EXTRA_KEYS)
    for key in unused:
        problems.append(f"unused key: {key!r}")
    for p in problems:
        print(p)
    print(f"{len(keys)} keys checked, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
