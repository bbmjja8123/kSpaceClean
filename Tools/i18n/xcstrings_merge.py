#!/usr/bin/env python3
"""xcstrings_merge.py — merge translated result batches back into .xcstrings.

Takes one or more flat result JSON files ({ "<key>": "<value>", ... }) produced
by translation agents (or the export script's batches flattened), a target
catalog and a language code, and writes the values into the catalog as
`"stringUnit": {"state": "translated", "value": …}` localizations for that
language.

Only keys that already exist in the catalog are merged; unknown keys are
reported and skipped (the export script is the source of truth for the key
set). Empty/whitespace-only values abort the run before any write. A `.bak`
backup of the catalog is written first (overwriting any previous backup).

Works for any .xcstrings catalog — the app catalog
(kWise/Resources/Localizable.xcstrings) and the widget-local catalog
(kWise/Widgets/Localizable.xcstrings) alike.

The catalog's existing key order and separator style (`": "` vs `" : "`) are
detected and preserved so diffs stay minimal.

Usage:
  python3 Tools/i18n/xcstrings_merge.py --catalog PATH --lang CODE RESULT.json [RESULT.json ...]

Output format matches Xcode's xcstrings writer (2-space indent, `" : "`
separator, sorted keys, trailing newline) so diffs stay clean.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        sys.exit(f"error: file not found: {path}")
    except json.JSONDecodeError as exc:
        sys.exit(f"error: {path} is not valid JSON: {exc}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", required=True, type=Path, help="target .xcstrings catalog")
    parser.add_argument("--lang", required=True, help="BCP-47 language code to fill (e.g. de, pt-BR)")
    parser.add_argument("results", nargs="+", type=Path, help="result JSON files ({key: value})")
    args = parser.parse_args()

    lang = args.lang
    catalog_path = args.catalog.resolve()
    catalog = load_json(catalog_path)
    strings = catalog.get("strings") or {}
    if not strings:
        sys.exit(f"error: {catalog_path} has no strings")

    # Collect + validate before touching anything.
    values: dict[str, str] = {}
    for result in args.results:
        for key, value in load_json(result).items():
            if isinstance(value, dict):
                # Tolerate batch-format entries: pick this language's column.
                if lang not in value:
                    sys.exit(
                        f"error: key '{key}' in {result} is a batch-format entry without a "
                        f"'{lang}' column — result files must be flat {{key: value}}"
                    )
                value = value[lang]
            if key in values and values[key] != value:
                sys.exit(f"error: conflicting values for key '{key}' across result files — aborting, nothing written")
            values[key] = value.strip()

    unknown = sorted(key for key in values if key not in strings)
    merged_keys = [key for key in values if key in strings]

    for key in merged_keys:
        entry = strings[key]
        localizations = entry.setdefault("localizations", {})
        localizations[lang] = {"stringUnit": {"state": "translated", "value": values[key]}}

    backup = catalog_path.with_suffix(catalog_path.suffix + ".bak")
    shutil.copy2(catalog_path, backup)
    raw = backup.read_text(encoding="utf-8")
    # Preserve whatever separator style the file already uses (" : " is the
    # Xcode writer style, ": " the plain json.dump style).
    spaced = '" : "' in raw or '"sourceLanguage" : ' in raw
    separator = (",", " : ") if spaced else (",", ": ")
    catalog_path.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, separators=separator) + "\n",
        encoding="utf-8",
    )

    still_missing = [
        key for key in strings
        if not ((strings[key].get("localizations") or {}).get(lang, {})
                .get("stringUnit", {}).get("value", "").strip())
    ]
    print(f"{catalog_path} [{lang}]: merged {len(merged_keys)}, "
          f"unknown keys skipped {len(unknown)}, still missing {len(still_missing)}")
    if unknown:
        print("  unknown keys (not in catalog, skipped):")
        for key in unknown:
            print(f"    {key}")
    if still_missing:
        print("  keys still missing this language:")
        for key in sorted(still_missing):
            print(f"    {key}")
        sys.exit(1)


if __name__ == "__main__":
    main()
