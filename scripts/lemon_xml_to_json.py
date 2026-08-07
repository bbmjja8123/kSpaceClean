#!/usr/bin/env python3
"""Build kSpaceClean's Bundle ID → app metadata mapping from Lemon's rule XML.

Task B1. This script performs a *data extraction*, not a code port: it reads the
plain-text cleaning-rule XML that ships with Lemon, pulls out the app names and
the filesystem paths those rules point at, and re-derives a bundle-ID-keyed
mapping in kSpaceClean's own schema. No Objective-C/C++ logic is translated or
reused (CLAUDE.md §2.5 / §6.1) — only the factual path/name data is carried over.

Reality check vs. the original task brief
-----------------------------------------
The brief assumed a ``BundleIDMap.xml`` with ``<app id=... name=... />`` rows.
No such file exists in the Lemon tree. The real data lives in the localized
cleaning-rule files::

    libcleaner/{zh-Hans,en}.lproj/garbage1.xml
    libcleaner/{zh-Hans,en}.lproj/garbage_appstore.xml
    libcleaner/garbage.xml

whose shape is ``garbage > category > item > action > path``. Bundle IDs are not
attributes at all — they are embedded inside the path strings (e.g.
``~/Library/Containers/com.tencent.xinWeChat/Data/...``). So this converter has
to *infer* the bundle ID for each item by mining reverse-DNS tokens out of its
paths, then merge the Chinese and English localizations to populate ``name`` and
``nameCN``. That inference is the reason for the ``confidence`` field on each
record.

Output schema (``bundleIDMapping.json``)::

    {
      "version": 1,
      "generatedAt": "YYYY-MM-DD",
      "source": "...",
      "apps": {
        "<bundleID>": {
          "bundleID":   str,
          "name":       str,   # English display name
          "nameCN":     str,   # Simplified Chinese display name
          "vendor":     str,   # inferred from the bundle ID's org token
          "type":       str,   # browser | chat | media | developer | ...
          "riskLevel":  str,   # recommended | optional | caution | dangerous
          "cleanPaths": [str], # tilde-relative or absolute path prefixes
          "confidence": str    # high | medium — how sure the bundleID inference is
        }
      }
    }
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import xml.etree.ElementTree as ET
from collections import OrderedDict

# --------------------------------------------------------------------------
# Source layout
# --------------------------------------------------------------------------

# (relative path, locale) pairs. ``None`` locale means the file is unlocalized
# and its titles are treated as Chinese (the base garbage.xml is zh-only).
SOURCE_FILES = [
    ("zh-Hans.lproj/garbage1.xml", "zh"),
    ("zh-Hans.lproj/garbage_appstore.xml", "zh"),
    ("en.lproj/garbage1.xml", "en"),
    ("en.lproj/garbage_appstore.xml", "en"),
    ("garbage.xml", "zh"),
]

# Reverse-DNS token that looks like a bundle identifier. Requires at least two
# dot-separated components after a known TLD-ish prefix so we do not match
# ordinary dotted filenames such as ``Cache.db-wal``.
BUNDLE_ID_RE = re.compile(
    r"\b(?:com|net|org|io|cn|us|de|jp|me|co|app|tv)\."
    r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+"
)

# Trailing regex fragments that Lemon embeds in path values (e.g. ``(.+)/``).
# They are matcher syntax, not real directories, so we truncate at that point
# and keep the stable prefix — kSpaceClean does prefix matching, not regex.
REGEX_FRAGMENT_RE = re.compile(r"[(\[*?+^$|\\]")

# Bundle IDs that are structurally valid but are not really *apps* we want to
# key the map on (they are Apple subsystem/database artefacts).
BUNDLE_ID_DENYLIST = {
    "com.apple.LaunchServices.QuarantineEvents",
    "com.apple.LaunchServices.QuarantineEventsV2",
}

# --------------------------------------------------------------------------
# Classification tables
#
# These encode kSpaceClean's own product policy (§8.5 four-level risk model).
# Lemon only had a two-level recommend YES/NO flag, so the mapping below is a
# deliberate re-grading rather than a copy of Lemon's behaviour.
# --------------------------------------------------------------------------

VENDOR_BY_ORG = {
    "apple": "Apple",
    "tencent": "腾讯",
    "alibaba": "阿里巴巴",
    "dingtalk": "阿里巴巴",
    "baidu": "百度",
    "netease": "网易",
    "sogou": "搜狗",
    "iflytek": "科大讯飞",
    "kugou": "酷狗",
    "xiami": "虾米音乐",
    "iqiyi": "爱奇艺",
    "pptv": "PPTV",
    "baofeng": "暴风影音",
    "google": "Google",
    "microsoft": "Microsoft",
    "operasoftware": "Opera Software",
    "mozilla": "Mozilla",
    "bohemiancoding": "Bohemian Coding",
    "hujiang": "沪江",
    "xianghu": "沪江",
    "wenyu": "酷我",
    "rockysandstudio": "Rocky Sand Studio",
}

# Substring → category type. Checked against the lowercased bundle ID.
TYPE_RULES = [
    (("safari", "chrome", "firefox", "opera", "browser", "qqbrowser"), "browser"),
    (("xcode", "dt.xcode", "intellij", "jetbrains", "androidstudio"), "developer"),
    (("wechat", "xinwechat", ".qq", "dingtalk", "wework", "cctalk"), "chat"),
    (("music", "163music", "qqmusic", "xiami", "kugou", "kwplayer"), "music"),
    (("video", "player", "iqiyi", "pptv", "tenvideo", "baofeng", "mkplayer"), "video"),
    (("mail",), "mail"),
    (("input", "inputmethod", "macinput", "sogoupad"), "inputmethod"),
    (("sketch", "photoshop", "adobe"), "design"),
]

# Path-shape → risk level. First match wins; checked against the lowercased path.
# Rationale is kSpaceClean's own: caches regenerate freely (recommended), while
# anything that holds user-visible content or login state is graded up.
# Tokens are matched as standalone words (``\\b``) so the literal string
# "downloads.plist" in a library folder does not trip the `/downloads` rule.
RISK_RULES = [
    (("/trash", ".trash"), "caution"),
    (("application support",), "caution"),
    (("\\b/documents\\b", "\\b/downloads\\b", "\\b/desktop\\b", "\\b/documents/", "\\b/downloads/", "\\b/desktop/"), "dangerous"),
    (("derivedddata", "deriveddata", "devicesupport", "archives"), "optional"),
    (("\\b/logs\\b", "\\b/log\\b", "diagnosticreports"), "recommended"),
    (("\\b/caches\\b", "\\b/cache\\b", "\\btmp\\b", "\\btemp\\b"), "recommended"),
]

# App-level risk floors. Some apps store irreplaceable user data inside what
# nominally looks like a cache directory (WeChat's Application Support tree is
# the classic example), so their records never grade below this.
RISK_FLOOR_BY_BUNDLE_ID = {
    "com.tencent.xinWeChat": "caution",
    "com.tencent.qq": "caution",
    "com.apple.mail": "caution",
}

RISK_ORDER = {"recommended": 0, "optional": 1, "caution": 2, "dangerous": 3}


# --------------------------------------------------------------------------
# Extraction helpers
# --------------------------------------------------------------------------


def _text(elem) -> str:
    """Return the trimmed text of an element, tolerating CDATA and absence."""
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def normalize_path(raw: str) -> str | None:
    """Reduce a Lemon path value to a stable literal prefix.

    Lemon path values may embed regex fragments (``(.+)/``) or reference symbolic
    locations (``SystemTempDir``). kSpaceClean matches by literal prefix, so we
    keep everything up to the first regex metacharacter and drop values that end
    up too short to be meaningful.
    """
    if not raw:
        return None
    value = raw.strip()
    if not value:
        return None
    # Symbolic (non-filesystem) locations are resolved at runtime, not here.
    if not value.startswith(("/", "~")):
        return None
    match = REGEX_FRAGMENT_RE.search(value)
    if match:
        value = value[: match.start()]
    value = value.rstrip("/")
    # "/Library" or "~" alone is too broad to attribute to a single app.
    if value.count("/") < 2:
        return None
    return value


def extract_bundle_ids(paths: list[str]) -> list[str]:
    """Mine reverse-DNS bundle identifiers out of a set of path strings.

    Returns them in first-seen order so the earliest (usually the container
    root) wins when we pick a primary ID.
    """
    found: OrderedDict[str, None] = OrderedDict()
    for path in paths:
        for candidate in BUNDLE_ID_RE.findall(path):
            candidate = candidate.rstrip(".")
            if candidate in BUNDLE_ID_DENYLIST:
                continue
            found.setdefault(candidate, None)
    return list(found.keys())


def pick_primary_bundle_id(candidates: list[str], paths: list[str]) -> str | None:
    """Choose the identifier that best represents an item.

    The rule for primary bundle ID is *occurrence count across the item's
    paths*, not shortest-first: a CCtalk item whose rules all reference
    ``com.hujiang.mac.cctalk`` should not collapse onto ``com.dingtalk.mac``
    just because the latter is a shorter string. Ties break on first-seen
    order, and an empty candidate list returns ``None``.
    """
    if not candidates:
        return None
    counts = {candidate: 0 for candidate in candidates}
    for path in paths:
        for candidate in candidates:
            if candidate in path:
                counts[candidate] += 1
    # ``max`` with a tuple key encodes (occurrences desc, first-seen asc).
    return max(
        candidates,
        key=lambda c: (counts[c], -candidates.index(c)),
    )


def infer_vendor(bundle_id: str) -> str:
    parts = bundle_id.split(".")
    if len(parts) < 2:
        return ""
    org = parts[1].lower()
    if org in VENDOR_BY_ORG:
        return VENDOR_BY_ORG[org]
    # Fall back to a title-cased organisation token ("bohemiancoding" → "Bohemiancoding").
    return parts[1].capitalize()


def infer_type(bundle_id: str) -> str:
    lowered = bundle_id.lower()
    for needles, type_name in TYPE_RULES:
        if any(needle in lowered for needle in needles):
            return type_name
    return "other"


def infer_risk_level(bundle_id: str, paths: list[str], recommended: bool) -> str:
    """Grade an app's cleaning risk on kSpaceClean's four-level scale."""
    level = "recommended" if recommended else "optional"
    for path in paths:
        lowered = path.lower()
        for needles, candidate in RISK_RULES:
            if any(needle in lowered for needle in needles):
                if RISK_ORDER[candidate] > RISK_ORDER[level]:
                    level = candidate
                break
    floor = RISK_FLOOR_BY_BUNDLE_ID.get(bundle_id)
    if floor and RISK_ORDER[floor] > RISK_ORDER[level]:
        level = floor
    return level


def parse_items(xml_path: str) -> list[dict]:
    """Read one Lemon rule file into flat item records.

    Each record carries the item's display title, its recommend flag, and every
    normalized path any of its actions reference.
    """
    root = ET.parse(xml_path).getroot()
    records = []
    for category in root.findall("category"):
        category_title = _text(category.find("title"))
        for item in category.findall("item"):
            title = _text(item.find("title"))
            if not title:
                continue
            paths: list[str] = []
            for action in item.findall("action"):
                for path_elem in action.findall("path"):
                    normalized = normalize_path(path_elem.get("value") or "")
                    if normalized and normalized not in paths:
                        paths.append(normalized)
            if not paths:
                continue
            records.append(
                {
                    "itemID": item.get("id") or "",
                    "title": title,
                    "category": category_title,
                    "recommend": (item.get("recommend") or "").upper() != "NO",
                    "paths": paths,
                }
            )
    return records


# --------------------------------------------------------------------------
# Merge
# --------------------------------------------------------------------------


def build_mapping(source_root: str) -> tuple[dict, dict]:
    """Parse every source file and fold the items into a bundle-ID-keyed map."""
    # itemID → {"zh": title, "en": title, paths, recommend}
    by_item: dict[str, dict] = {}
    stats = {"filesParsed": 0, "itemsSeen": 0, "itemsWithoutBundleID": 0}

    for rel_path, locale in SOURCE_FILES:
        full_path = os.path.join(source_root, rel_path)
        if not os.path.exists(full_path):
            print(f"  ! skipping missing source: {rel_path}")
            continue
        stats["filesParsed"] += 1
        for record in parse_items(full_path):
            # Item IDs are stable across localizations, which is what lets us
            # join the zh and en titles onto a single record.
            key = record["itemID"] or f"{rel_path}:{record['title']}"
            entry = by_item.setdefault(
                key,
                {"titles": {}, "paths": [], "recommend": record["recommend"]},
            )
            entry["titles"].setdefault(locale, record["title"])
            for path in record["paths"]:
                if path not in entry["paths"]:
                    entry["paths"].append(path)
            entry["recommend"] = entry["recommend"] and record["recommend"]

    apps: dict[str, dict] = {}
    for entry in by_item.values():
        stats["itemsSeen"] += 1
        candidates = extract_bundle_ids(entry["paths"])
        primary = pick_primary_bundle_id(candidates, entry["paths"])
        if primary is None:
            # Generic system rules (e.g. "/Library/Logs") belong to no single
            # app; they are handled by the scan rule engine, not this resolver.
            stats["itemsWithoutBundleID"] += 1
            continue

        name_en = entry["titles"].get("en", "")
        name_cn = entry["titles"].get("zh", "")
        # If only one localization exists, mirror it so neither field is blank.
        name_en = name_en or name_cn
        name_cn = name_cn or name_en

        record = apps.get(primary)
        if record is None:
            record = {
                "bundleID": primary,
                "name": name_en,
                "nameCN": name_cn,
                "vendor": infer_vendor(primary),
                "type": infer_type(primary),
                "riskLevel": infer_risk_level(primary, entry["paths"], entry["recommend"]),
                "cleanPaths": [],
                # "high" when the bundle ID was the only reverse-DNS token in the
                # item's paths; "medium" when we had to disambiguate several.
                "confidence": "high" if len(candidates) == 1 else "medium",
            }
            apps[primary] = record
        else:
            # Two items map to the same app: keep the stricter risk grade.
            merged_risk = infer_risk_level(primary, entry["paths"], entry["recommend"])
            if RISK_ORDER[merged_risk] > RISK_ORDER[record["riskLevel"]]:
                record["riskLevel"] = merged_risk
            if not record["name"]:
                record["name"] = name_en
            if not record["nameCN"]:
                record["nameCN"] = name_cn

        for path in entry["paths"]:
            if path not in record["cleanPaths"]:
                record["cleanPaths"].append(path)

    for record in apps.values():
        record["cleanPaths"].sort()

    stats["appsMapped"] = len(apps)
    return apps, stats


def convert(source_root: str, json_path: str) -> int:
    apps, stats = build_mapping(source_root)
    document = {
        "version": 1,
        "generatedAt": _dt.date.today().isoformat(),
        "source": "Lemon libcleaner cleaning-rule XML (data extraction only)",
        "apps": OrderedDict(sorted(apps.items())),
    }
    os.makedirs(os.path.dirname(os.path.abspath(json_path)), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, indent=2, sort_keys=False)
        handle.write("\n")

    print(f"  files parsed:          {stats['filesParsed']}")
    print(f"  items seen:            {stats['itemsSeen']}")
    print(f"  items w/o bundle ID:   {stats['itemsWithoutBundleID']} (generic system rules)")
    print(f"  apps mapped:           {stats['appsMapped']}")
    print(f"  wrote:                 {json_path}")
    return stats["appsMapped"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source_root",
        help="Path to Lemon's libcleaner directory (contains garbage.xml and *.lproj/).",
    )
    parser.add_argument("output", help="Destination bundleIDMapping.json path.")
    args = parser.parse_args()
    convert(args.source_root, args.output)


if __name__ == "__main__":
    main()
