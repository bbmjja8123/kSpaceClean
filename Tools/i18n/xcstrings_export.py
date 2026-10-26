#!/usr/bin/env python3
"""xcstrings_export.py — export missing-translation batches from .xcstrings catalogs.

Reads one or more .xcstrings catalogs and, for each requested target language,
writes a JSON batch file listing every key that is missing (or empty) in that
language. Each batch entry carries the three reference languages (en / zh-Hans
/ ja) so translation agents can work from source + sibling translations:

    {
      "<key>": {"en": "<en value>", "zh-Hans": "<zh value>", "ja": "<ja value>"},
      ...
    }

Batch file naming:
  - the default catalog (kWise/Resources/Localizable.xcstrings) → <lang>.json
  - any other catalog → "<dir-prefix>-<lang>.json", where the prefix is the
    catalog's parent directory lowercased, trailing "s" stripped
    (e.g. kWise/Widgets/… → widget-<lang>.json)

Idempotent: re-running on the same catalog reproduces byte-identical batches
(sorted keys, sorted output). Keys with extractionState "stale" are included —
the LocalizationCompletenessTests gate iterates every key in the catalog.

Usage:
  python3 Tools/i18n/xcstrings_export.py \
      [--catalog PATH]... [--langs en,fr,...] [--out-dir DIR]

Defaults: both kWise catalogs (app + widget-local), the 9 rollout languages
(zh-Hant ko de fr es pt-BR it ru ar), out dir /tmp/i18n-batches.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOGS = [
    REPO_ROOT / "kWise/Resources/Localizable.xcstrings",
    REPO_ROOT / "kWise/Widgets/Localizable.xcstrings",
]
DEFAULT_LANGS = ["zh-Hant", "ko", "de", "fr", "es", "pt-BR", "it", "ru", "ar"]
REFERENCE_LANGS = ["en", "zh-Hans", "ja"]
DEFAULT_OUT_DIR = Path("/tmp/i18n-batches")


def load_catalog(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        sys.exit(f"error: catalog not found: {path}")
    except json.JSONDecodeError as exc:
        sys.exit(f"error: {path} is not valid JSON: {exc}")


def string_unit_value(entry: dict, lang: str) -> str | None:
    """Return the translated value for `lang`, or None if missing/empty."""
    unit = (entry.get("localizations") or {}).get(lang, {}).get("stringUnit") or {}
    value = unit.get("value")
    if value is None:
        return None
    value = value.strip()
    return value or None


def batch_name_for(catalog: Path) -> str:
    dir_name = catalog.parent.name.lower().rstrip("s")
    prefix = "" if dir_name in ("resource", ".") else dir_name + "-"
    return prefix + "{lang}.json"


def export_batch(catalog_path: Path, langs: list[str], out_dir: Path) -> None:
    catalog = load_catalog(catalog_path)
    strings = catalog.get("strings") or {}
    if not strings:
        sys.exit(f"error: {catalog_path} has no strings")

    missing_refs: set[str] = set()

    name_template = batch_name_for(catalog_path)
    counts: dict[str, int] = {}
    for lang in langs:
        batch = {}
        for key in sorted(strings):
            if string_unit_value(strings[key], lang) is not None:
                continue
            refs = {}
            for ref_lang in REFERENCE_LANGS:
                value = string_unit_value(strings[key], ref_lang)
                if value is not None:
                    refs[ref_lang] = value
                else:
                    missing_refs.add(ref_lang)
            batch[key] = refs
        counts[lang] = len(batch)
        out_path = out_dir / name_template.format(lang=lang)
        out_path.write_text(
            json.dumps(batch, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    label = catalog_path.relative_to(REPO_ROOT) if catalog_path.is_relative_to(REPO_ROOT) else catalog_path
    print(f"{label}: {len(strings)} keys total")
    for lang in langs:
        print(f"  {lang}: {counts[lang]} missing -> {out_dir / name_template.format(lang=lang)}")
    if missing_refs:
        print(
            f"  WARNING: reference languages missing for some keys in {catalog_path}: "
            f"{', '.join(sorted(missing_refs))} (batches omit those columns)",
            file=sys.stderr,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--catalog", action="append", default=[], type=Path,
        help="catalog to export (repeatable; default: kWise app + widget catalogs)",
    )
    parser.add_argument(
        "--langs", default=",".join(DEFAULT_LANGS),
        help="comma-separated target languages (default: the 9 rollout languages)",
    )
    parser.add_argument(
        "--out-dir", type=Path, default=DEFAULT_OUT_DIR,
        help=f"output directory (default: {DEFAULT_OUT_DIR})",
    )
    args = parser.parse_args()

    catalogs = args.catalog or DEFAULT_CATALOGS
    langs = [lang.strip() for lang in args.langs.split(",") if lang.strip()]
    if not langs:
        sys.exit("error: no languages requested")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    for catalog in catalogs:
        export_batch(catalog.resolve(), langs, args.out_dir)


if __name__ == "__main__":
    main()
